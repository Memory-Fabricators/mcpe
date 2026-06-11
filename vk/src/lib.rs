// Rust 2024: unsafe fn bodies are no longer implicitly unsafe blocks.
// Since every function here is a raw Vulkan wrapper, allow this globally.
#![allow(unsafe_op_in_unsafe_fn)]

extern crate ash;
extern crate glam;

use ash::{khr, vk, Device, Entry, Instance};
use glam::Mat4;
use std::os::raw::{c_int, c_void};

// ---------------------------------------------------------------------------
// Compiled SPIR-V, embedded at build time
// ---------------------------------------------------------------------------
const SPV_TERRAIN_VERT: &[u8] = include_bytes!("../shaders/terrain.vert.spv");
const SPV_TERRAIN_FRAG: &[u8] = include_bytes!("../shaders/terrain.frag.spv");
const SPV_TERRAIN_ALPHA_FRAG: &[u8] = include_bytes!("../shaders/terrain_alpha.frag.spv");
const SPV_GUI_FRAG: &[u8] = include_bytes!("../shaders/gui.frag.spv");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const MAX_FRAMES: usize = 2;
const MAX_TEXTURES: usize = 1024;
/// 32 MiB dynamic vertex buffer – reset each frame
const VTX_BUF_BYTES: vk::DeviceSize = 32 * 1024 * 1024;
const MAX_VERTS: usize = VTX_BUF_BYTES as usize / size_of::<Vertex>();

// Pipeline indices
const PIPE_OPAQUE: usize = 0;
const PIPE_ALPHA: usize = 1;
const PIPE_TRANSPARENT: usize = 2;
const PIPE_GUI: usize = 3;
const PIPE_ITEMS: usize = 4;

// ---------------------------------------------------------------------------
// Vertex layout – must match VertexDeclPTC (24 bytes)
// ---------------------------------------------------------------------------
#[repr(C)]
struct Vertex {
    pos: [f32; 3], // offset  0
    uv: [f32; 2],  // offset 12
    color: u32,    // offset 20  (ABGR packed = R8G8B8A8_UNORM in memory)
}

// ---------------------------------------------------------------------------
// Fog uniform buffer (std140)
// ---------------------------------------------------------------------------
#[repr(C)]
struct FogUbo {
    color: [f32; 4], //  0 – 15
    start: f32,      // 16
    end: f32,        // 20
    density: f32,    // 24
    mode: u32,       // 28  (0=off  1=linear  2=exp)
}

// ---------------------------------------------------------------------------
// Fog state (CPU side)
// ---------------------------------------------------------------------------
enum FogState {
    Off,
    Linear {
        start: f32,
        end: f32,
        r: f32,
        g: f32,
        b: f32,
    },
    Exp {
        density: f32,
        r: f32,
        g: f32,
        b: f32,
    },
}

// ---------------------------------------------------------------------------
// Per-texture GPU resources
// ---------------------------------------------------------------------------
struct TextureEntry {
    image: vk::Image,
    memory: vk::DeviceMemory,
    view: vk::ImageView,
    desc_set: vk::DescriptorSet,
}

// ---------------------------------------------------------------------------
// Main renderer
// ---------------------------------------------------------------------------
struct Renderer {
    // Core
    entry: Entry,
    instance: Instance,
    pdev: vk::PhysicalDevice,
    dev: Device,
    q_family: u32,
    queue: vk::Queue,

    // Surface / swapchain
    surface_ext: khr::surface::Instance,
    surface: vk::SurfaceKHR,
    swapchain_ext: khr::swapchain::Device,
    swapchain: vk::SwapchainKHR,
    sc_images: Vec<vk::Image>,
    sc_views: Vec<vk::ImageView>,
    sc_format: vk::Format,
    extent: vk::Extent2D,

    // Depth
    depth_image: vk::Image,
    depth_mem: vk::DeviceMemory,
    depth_view: vk::ImageView,
    depth_format: vk::Format,

    // Render pass + framebuffers
    render_pass: vk::RenderPass,
    framebuffers: Vec<vk::Framebuffer>,

    // Commands
    cmd_pool: vk::CommandPool,
    cmd_bufs: [vk::CommandBuffer; MAX_FRAMES],

    // Sync
    img_available: [vk::Semaphore; MAX_FRAMES],
    render_done: [vk::Semaphore; MAX_FRAMES],
    in_flight: [vk::Fence; MAX_FRAMES],

    // Descriptors
    desc_pool: vk::DescriptorPool,
    fog_layout: vk::DescriptorSetLayout,
    tex_layout: vk::DescriptorSetLayout,
    pipe_layout: vk::PipelineLayout,

    // Fog UBOs (one per frame)
    fog_bufs: [vk::Buffer; MAX_FRAMES],
    fog_mems: [vk::DeviceMemory; MAX_FRAMES],
    fog_ptrs: [*mut FogUbo; MAX_FRAMES],
    fog_sets: [vk::DescriptorSet; MAX_FRAMES],

    // Dynamic vertex buffer
    vtx_buf: vk::Buffer,
    vtx_mem: vk::DeviceMemory,
    vtx_ptr: *mut Vertex,
    vtx_head: usize, // vertices written this frame

    // Pipelines: [opaque, alpha_test, transparent, gui, items]
    pipelines: [vk::Pipeline; 5],

    // Sampler shared by all textures
    sampler: vk::Sampler,
    textures: Vec<TextureEntry>,

    // Chunk (persistent) vertex buffers; slot 0 unused, id = index
    chunks: Vec<Option<(vk::Buffer, vk::DeviceMemory)>>,

    // Per-frame tracking
    frame: usize,
    image_idx: u32,
    cur_cmd: vk::CommandBuffer,

    // Render state
    clear_color: [f32; 4],
    projection: Mat4,
    modelview: Mat4,
    mat_stack: Vec<Mat4>,
    cur_pipeline: usize,
    cur_tex: u32,

    // Fog
    fog: FogState,
    fog_dirty: bool,

    // Scissor
    scissor_on: bool,
    scissor: vk::Rect2D,
}

// SAFETY: called exclusively from the single game-render thread via C FFI
unsafe impl Send for Renderer {}
unsafe impl Sync for Renderer {}

static mut RENDERER: Option<Box<Renderer>> = None;

#[inline(always)]
fn r() -> &'static mut Renderer {
    // Use addr_of_mut! to avoid the Rust 2024 "mutable reference to mutable
    // static" lint while still getting the &mut we need.
    unsafe {
        let p = std::ptr::addr_of_mut!(RENDERER);
        (*p).as_mut().expect("vk renderer not initialised")
    }
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------
fn find_memory_type(
    props: &vk::PhysicalDeviceMemoryProperties,
    type_bits: u32,
    flags: vk::MemoryPropertyFlags,
) -> u32 {
    for i in 0..props.memory_type_count {
        if (type_bits & (1 << i)) != 0
            && props.memory_types[i as usize].property_flags.contains(flags)
        {
            return i;
        }
    }
    panic!("no suitable memory type");
}

unsafe fn create_buffer(
    dev: &Device,
    mem_props: &vk::PhysicalDeviceMemoryProperties,
    size: vk::DeviceSize,
    usage: vk::BufferUsageFlags,
    flags: vk::MemoryPropertyFlags,
) -> (vk::Buffer, vk::DeviceMemory, *mut u8) {
    let buf = dev
        .create_buffer(
            &vk::BufferCreateInfo::default().size(size).usage(usage),
            None,
        )
        .unwrap();
    let req = dev.get_buffer_memory_requirements(buf);
    let mem = dev
        .allocate_memory(
            &vk::MemoryAllocateInfo::default()
                .allocation_size(req.size)
                .memory_type_index(find_memory_type(mem_props, req.memory_type_bits, flags)),
            None,
        )
        .unwrap();
    dev.bind_buffer_memory(buf, mem, 0).unwrap();
    let ptr = if flags.contains(vk::MemoryPropertyFlags::HOST_VISIBLE) {
        dev.map_memory(mem, 0, size, vk::MemoryMapFlags::empty())
            .unwrap() as *mut u8
    } else {
        std::ptr::null_mut()
    };
    (buf, mem, ptr)
}

unsafe fn create_image_2d(
    dev: &Device,
    mem_props: &vk::PhysicalDeviceMemoryProperties,
    w: u32,
    h: u32,
    format: vk::Format,
    usage: vk::ImageUsageFlags,
    tiling: vk::ImageTiling,
    mem_flags: vk::MemoryPropertyFlags,
) -> (vk::Image, vk::DeviceMemory) {
    let img = dev
        .create_image(
            &vk::ImageCreateInfo::default()
                .image_type(vk::ImageType::TYPE_2D)
                .format(format)
                .extent(vk::Extent3D {
                    width: w,
                    height: h,
                    depth: 1,
                })
                .mip_levels(1)
                .array_layers(1)
                .samples(vk::SampleCountFlags::TYPE_1)
                .tiling(tiling)
                .usage(usage)
                .initial_layout(vk::ImageLayout::UNDEFINED),
            None,
        )
        .unwrap();
    let req = dev.get_image_memory_requirements(img);
    let mem = dev
        .allocate_memory(
            &vk::MemoryAllocateInfo::default()
                .allocation_size(req.size)
                .memory_type_index(find_memory_type(mem_props, req.memory_type_bits, mem_flags)),
            None,
        )
        .unwrap();
    dev.bind_image_memory(img, mem, 0).unwrap();
    (img, mem)
}

unsafe fn image_barrier(
    dev: &Device,
    cmd: vk::CommandBuffer,
    image: vk::Image,
    aspect: vk::ImageAspectFlags,
    old_layout: vk::ImageLayout,
    new_layout: vk::ImageLayout,
    src_stage: vk::PipelineStageFlags,
    dst_stage: vk::PipelineStageFlags,
    src_access: vk::AccessFlags,
    dst_access: vk::AccessFlags,
) {
    let barrier = vk::ImageMemoryBarrier::default()
        .old_layout(old_layout)
        .new_layout(new_layout)
        .src_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
        .dst_queue_family_index(vk::QUEUE_FAMILY_IGNORED)
        .image(image)
        .subresource_range(
            vk::ImageSubresourceRange::default()
                .aspect_mask(aspect)
                .base_mip_level(0)
                .level_count(1)
                .base_array_layer(0)
                .layer_count(1),
        )
        .src_access_mask(src_access)
        .dst_access_mask(dst_access);
    dev.cmd_pipeline_barrier(
        cmd,
        src_stage,
        dst_stage,
        vk::DependencyFlags::empty(),
        &[],
        &[],
        &[barrier],
    );
}

unsafe fn one_shot_begin(dev: &Device, pool: vk::CommandPool) -> vk::CommandBuffer {
    let cb = dev
        .allocate_command_buffers(
            &vk::CommandBufferAllocateInfo::default()
                .command_pool(pool)
                .level(vk::CommandBufferLevel::PRIMARY)
                .command_buffer_count(1),
        )
        .unwrap()[0];
    dev.begin_command_buffer(
        cb,
        &vk::CommandBufferBeginInfo::default()
            .flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT),
    )
    .unwrap();
    cb
}

unsafe fn one_shot_end(dev: &Device, pool: vk::CommandPool, queue: vk::Queue, cb: vk::CommandBuffer) {
    dev.end_command_buffer(cb).unwrap();
    let cbs = [cb];
    let submit = vk::SubmitInfo::default().command_buffers(&cbs);
    dev.queue_submit(queue, &[submit], vk::Fence::null()).unwrap();
    dev.queue_wait_idle(queue).unwrap();
    dev.free_command_buffers(pool, &cbs);
}

unsafe fn make_shader_module(dev: &Device, spv: &[u8]) -> vk::ShaderModule {
    let code: Vec<u32> = spv
        .chunks_exact(4)
        .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect();
    dev.create_shader_module(&vk::ShaderModuleCreateInfo::default().code(&code), None)
        .unwrap()
}

fn depth_format_for(instance: &Instance, pdev: vk::PhysicalDevice) -> vk::Format {
    for fmt in [
        vk::Format::D32_SFLOAT,
        vk::Format::D32_SFLOAT_S8_UINT,
        vk::Format::D24_UNORM_S8_UINT,
    ] {
        let props = unsafe { instance.get_physical_device_format_properties(pdev, fmt) };
        if props
            .optimal_tiling_features
            .contains(vk::FormatFeatureFlags::DEPTH_STENCIL_ATTACHMENT)
        {
            return fmt;
        }
    }
    panic!("no supported depth format");
}

// ---------------------------------------------------------------------------
// Renderer construction
// ---------------------------------------------------------------------------
impl Renderer {
    unsafe fn new(sdl_window: *mut c_void, width: u32, height: u32) -> Box<Self> {
        // SDL3 Vulkan bindings (declared inline to avoid a full sdl2/sdl3 dep)
        unsafe extern "C" {
            fn SDL_Vulkan_GetInstanceExtensions(count: *mut u32) -> *const *const i8;
            fn SDL_Vulkan_CreateSurface(
                window: *mut c_void,
                instance: vk::Instance,
                allocator: *const c_void,
                surface: *mut vk::SurfaceKHR,
            ) -> bool;
        }

        let entry = Entry::load().expect("failed to load Vulkan loader");

        // Get required instance extensions from SDL (handles X11/Wayland/etc)
        let mut ext_count: u32 = 0;
        let ext_names_ptr = SDL_Vulkan_GetInstanceExtensions(&mut ext_count);
        assert!(!ext_names_ptr.is_null(), "SDL_Vulkan_GetInstanceExtensions failed");
        let inst_extensions =
            std::slice::from_raw_parts(ext_names_ptr, ext_count as usize);

        // Instance ----------------------------------------------------------
        let app_info = vk::ApplicationInfo::default()
            .application_name(c"mcpe")
            .api_version(vk::API_VERSION_1_1);

        let instance = entry
            .create_instance(
                &vk::InstanceCreateInfo::default()
                    .application_info(&app_info)
                    .enabled_extension_names(inst_extensions),
                None,
            )
            .unwrap();

        // Surface via SDL (works on X11, Wayland, etc.) ---------------------
        let surface_ext = khr::surface::Instance::load(&entry, &instance);
        let mut surface = vk::SurfaceKHR::null();
        let ok = SDL_Vulkan_CreateSurface(sdl_window, instance.handle(), std::ptr::null(), &mut surface);
        assert!(ok, "SDL_Vulkan_CreateSurface failed");

        // Physical device ---------------------------------------------------
        let pdevs = instance.enumerate_physical_devices().unwrap();
        let pdev = pdevs
            .iter()
            .copied()
            .find(|&pd| {
                let props = instance.get_physical_device_properties(pd);
                props.device_type == vk::PhysicalDeviceType::DISCRETE_GPU
            })
            .unwrap_or(pdevs[0]);

        // Queue family (graphics + present) ---------------------------------
        let qfamilies = instance.get_physical_device_queue_family_properties(pdev);
        let q_family = qfamilies
            .iter()
            .enumerate()
            .position(|(i, q)| {
                q.queue_flags.contains(vk::QueueFlags::GRAPHICS)
                    && surface_ext
                        .get_physical_device_surface_support(pdev, i as u32, surface)
                        .unwrap_or(false)
            })
            .expect("no graphics+present queue") as u32;

        // Logical device ----------------------------------------------------
        let q_prios = [1.0f32];
        let q_info = vk::DeviceQueueCreateInfo::default()
            .queue_family_index(q_family)
            .queue_priorities(&q_prios);
        let dev_extensions = [khr::swapchain::NAME.as_ptr()];
        let dev = instance
            .create_device(
                pdev,
                &vk::DeviceCreateInfo::default()
                    .queue_create_infos(std::slice::from_ref(&q_info))
                    .enabled_extension_names(&dev_extensions),
                None,
            )
            .unwrap();
        let queue = dev.get_device_queue(q_family, 0);

        let mem_props = instance.get_physical_device_memory_properties(pdev);
        let depth_format = depth_format_for(&instance, pdev);

        // Swapchain ---------------------------------------------------------
        let swapchain_ext = khr::swapchain::Device::load(&instance, &dev);
        let surface_caps = surface_ext
            .get_physical_device_surface_capabilities(pdev, surface)
            .unwrap();
        let surface_formats = surface_ext
            .get_physical_device_surface_formats(pdev, surface)
            .unwrap();
        let present_modes = surface_ext
            .get_physical_device_surface_present_modes(pdev, surface)
            .unwrap();

        let sc_format = surface_formats
            .iter()
            .find(|f| {
                f.format == vk::Format::B8G8R8A8_UNORM
                    && f.color_space == vk::ColorSpaceKHR::SRGB_NONLINEAR
            })
            .copied()
            .unwrap_or(surface_formats[0]);

        let present_mode = if present_modes.contains(&vk::PresentModeKHR::MAILBOX) {
            vk::PresentModeKHR::MAILBOX
        } else {
            vk::PresentModeKHR::FIFO
        };

        let extent = vk::Extent2D {
            width: width.clamp(
                surface_caps.min_image_extent.width,
                surface_caps.max_image_extent.width,
            ),
            height: height.clamp(
                surface_caps.min_image_extent.height,
                surface_caps.max_image_extent.height,
            ),
        };

        let img_count = (surface_caps.min_image_count + 1)
            .min(if surface_caps.max_image_count == 0 {
                u32::MAX
            } else {
                surface_caps.max_image_count
            });

        let swapchain = swapchain_ext
            .create_swapchain(
                &vk::SwapchainCreateInfoKHR::default()
                    .surface(surface)
                    .min_image_count(img_count)
                    .image_format(sc_format.format)
                    .image_color_space(sc_format.color_space)
                    .image_extent(extent)
                    .image_array_layers(1)
                    .image_usage(vk::ImageUsageFlags::COLOR_ATTACHMENT)
                    .image_sharing_mode(vk::SharingMode::EXCLUSIVE)
                    .pre_transform(surface_caps.current_transform)
                    .composite_alpha(vk::CompositeAlphaFlagsKHR::OPAQUE)
                    .present_mode(present_mode)
                    .clipped(true),
                None,
            )
            .unwrap();

        let sc_images = swapchain_ext.get_swapchain_images(swapchain).unwrap();
        let sc_views: Vec<_> = sc_images
            .iter()
            .map(|&img| {
                dev.create_image_view(
                    &vk::ImageViewCreateInfo::default()
                        .image(img)
                        .view_type(vk::ImageViewType::TYPE_2D)
                        .format(sc_format.format)
                        .subresource_range(
                            vk::ImageSubresourceRange::default()
                                .aspect_mask(vk::ImageAspectFlags::COLOR)
                                .level_count(1)
                                .layer_count(1),
                        ),
                    None,
                )
                .unwrap()
            })
            .collect();

        // Depth image -------------------------------------------------------
        let (depth_image, depth_mem) = create_image_2d(
            &dev,
            &mem_props,
            extent.width,
            extent.height,
            depth_format,
            vk::ImageUsageFlags::DEPTH_STENCIL_ATTACHMENT,
            vk::ImageTiling::OPTIMAL,
            vk::MemoryPropertyFlags::DEVICE_LOCAL,
        );
        let depth_aspect = if depth_format == vk::Format::D32_SFLOAT {
            vk::ImageAspectFlags::DEPTH
        } else {
            vk::ImageAspectFlags::DEPTH | vk::ImageAspectFlags::STENCIL
        };
        let depth_view = dev
            .create_image_view(
                &vk::ImageViewCreateInfo::default()
                    .image(depth_image)
                    .view_type(vk::ImageViewType::TYPE_2D)
                    .format(depth_format)
                    .subresource_range(
                        vk::ImageSubresourceRange::default()
                            .aspect_mask(depth_aspect)
                            .level_count(1)
                            .layer_count(1),
                    ),
                None,
            )
            .unwrap();

        // Render pass -------------------------------------------------------
        let color_att = vk::AttachmentDescription::default()
            .format(sc_format.format)
            .samples(vk::SampleCountFlags::TYPE_1)
            .load_op(vk::AttachmentLoadOp::CLEAR)
            .store_op(vk::AttachmentStoreOp::STORE)
            .initial_layout(vk::ImageLayout::UNDEFINED)
            .final_layout(vk::ImageLayout::PRESENT_SRC_KHR);

        let depth_att = vk::AttachmentDescription::default()
            .format(depth_format)
            .samples(vk::SampleCountFlags::TYPE_1)
            .load_op(vk::AttachmentLoadOp::CLEAR)
            .store_op(vk::AttachmentStoreOp::DONT_CARE)
            .stencil_load_op(vk::AttachmentLoadOp::DONT_CARE)
            .stencil_store_op(vk::AttachmentStoreOp::DONT_CARE)
            .initial_layout(vk::ImageLayout::UNDEFINED)
            .final_layout(vk::ImageLayout::DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

        let color_ref = vk::AttachmentReference::default()
            .attachment(0)
            .layout(vk::ImageLayout::COLOR_ATTACHMENT_OPTIMAL);
        let depth_ref = vk::AttachmentReference::default()
            .attachment(1)
            .layout(vk::ImageLayout::DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

        let subpass = vk::SubpassDescription::default()
            .pipeline_bind_point(vk::PipelineBindPoint::GRAPHICS)
            .color_attachments(std::slice::from_ref(&color_ref))
            .depth_stencil_attachment(&depth_ref);

        let dependency = vk::SubpassDependency::default()
            .src_subpass(vk::SUBPASS_EXTERNAL)
            .dst_subpass(0)
            .src_stage_mask(
                vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT
                    | vk::PipelineStageFlags::EARLY_FRAGMENT_TESTS,
            )
            .dst_stage_mask(
                vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT
                    | vk::PipelineStageFlags::EARLY_FRAGMENT_TESTS,
            )
            .src_access_mask(vk::AccessFlags::empty())
            .dst_access_mask(
                vk::AccessFlags::COLOR_ATTACHMENT_WRITE
                    | vk::AccessFlags::DEPTH_STENCIL_ATTACHMENT_WRITE,
            );

        let render_pass = dev
            .create_render_pass(
                &vk::RenderPassCreateInfo::default()
                    .attachments(&[color_att, depth_att])
                    .subpasses(std::slice::from_ref(&subpass))
                    .dependencies(std::slice::from_ref(&dependency)),
                None,
            )
            .unwrap();

        // Framebuffers ------------------------------------------------------
        let framebuffers = sc_views
            .iter()
            .map(|&view| {
                let atts = [view, depth_view];
                dev.create_framebuffer(
                    &vk::FramebufferCreateInfo::default()
                        .render_pass(render_pass)
                        .attachments(&atts)
                        .width(extent.width)
                        .height(extent.height)
                        .layers(1),
                    None,
                )
                .unwrap()
            })
            .collect();

        // Command pool + buffers --------------------------------------------
        let cmd_pool = dev
            .create_command_pool(
                &vk::CommandPoolCreateInfo::default()
                    .queue_family_index(q_family)
                    .flags(vk::CommandPoolCreateFlags::RESET_COMMAND_BUFFER),
                None,
            )
            .unwrap();

        let cmd_bufs_vec = dev
            .allocate_command_buffers(
                &vk::CommandBufferAllocateInfo::default()
                    .command_pool(cmd_pool)
                    .level(vk::CommandBufferLevel::PRIMARY)
                    .command_buffer_count(MAX_FRAMES as u32),
            )
            .unwrap();
        let cmd_bufs = [cmd_bufs_vec[0], cmd_bufs_vec[1]];

        // Sync objects ------------------------------------------------------
        let sem_info = vk::SemaphoreCreateInfo::default();
        let fence_info =
            vk::FenceCreateInfo::default().flags(vk::FenceCreateFlags::SIGNALED);
        let img_available = [
            dev.create_semaphore(&sem_info, None).unwrap(),
            dev.create_semaphore(&sem_info, None).unwrap(),
        ];
        let render_done = [
            dev.create_semaphore(&sem_info, None).unwrap(),
            dev.create_semaphore(&sem_info, None).unwrap(),
        ];
        let in_flight = [
            dev.create_fence(&fence_info, None).unwrap(),
            dev.create_fence(&fence_info, None).unwrap(),
        ];

        // Descriptor set layouts --------------------------------------------
        let fog_binding = vk::DescriptorSetLayoutBinding::default()
            .binding(0)
            .descriptor_type(vk::DescriptorType::UNIFORM_BUFFER)
            .descriptor_count(1)
            .stage_flags(vk::ShaderStageFlags::FRAGMENT);
        let fog_layout = dev
            .create_descriptor_set_layout(
                &vk::DescriptorSetLayoutCreateInfo::default()
                    .bindings(std::slice::from_ref(&fog_binding)),
                None,
            )
            .unwrap();

        let tex_binding = vk::DescriptorSetLayoutBinding::default()
            .binding(0)
            .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
            .descriptor_count(1)
            .stage_flags(vk::ShaderStageFlags::FRAGMENT);
        let tex_layout = dev
            .create_descriptor_set_layout(
                &vk::DescriptorSetLayoutCreateInfo::default()
                    .bindings(std::slice::from_ref(&tex_binding)),
                None,
            )
            .unwrap();

        // Pipeline layout (push_constants=64B + set0=fog + set1=tex) --------
        let push_range = vk::PushConstantRange::default()
            .stage_flags(vk::ShaderStageFlags::VERTEX)
            .offset(0)
            .size(64); // one mat4
        let set_layouts = [fog_layout, tex_layout];
        let pipe_layout = dev
            .create_pipeline_layout(
                &vk::PipelineLayoutCreateInfo::default()
                    .set_layouts(&set_layouts)
                    .push_constant_ranges(std::slice::from_ref(&push_range)),
                None,
            )
            .unwrap();

        // Descriptor pool ---------------------------------------------------
        let pool_sizes = [
            vk::DescriptorPoolSize {
                ty: vk::DescriptorType::UNIFORM_BUFFER,
                descriptor_count: MAX_FRAMES as u32,
            },
            vk::DescriptorPoolSize {
                ty: vk::DescriptorType::COMBINED_IMAGE_SAMPLER,
                descriptor_count: MAX_TEXTURES as u32,
            },
        ];
        let desc_pool = dev
            .create_descriptor_pool(
                &vk::DescriptorPoolCreateInfo::default()
                    .max_sets(MAX_FRAMES as u32 + MAX_TEXTURES as u32)
                    .pool_sizes(&pool_sizes),
                None,
            )
            .unwrap();

        // Fog UBOs and descriptor sets --------------------------------------
        let mut fog_bufs = [vk::Buffer::null(); MAX_FRAMES];
        let mut fog_mems = [vk::DeviceMemory::null(); MAX_FRAMES];
        let mut fog_ptrs = [std::ptr::null_mut::<FogUbo>(); MAX_FRAMES];

        for i in 0..MAX_FRAMES {
            let (buf, mem, ptr) = create_buffer(
                &dev,
                &mem_props,
                size_of::<FogUbo>() as vk::DeviceSize,
                vk::BufferUsageFlags::UNIFORM_BUFFER,
                vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
            );
            fog_bufs[i] = buf;
            fog_mems[i] = mem;
            fog_ptrs[i] = ptr as *mut FogUbo;
            // initialise to fog-off
            fog_ptrs[i].write(FogUbo {
                color: [0.0; 4],
                start: 0.0,
                end: 0.0,
                density: 0.0,
                mode: 0,
            });
        }

        let fog_layouts = [fog_layout; MAX_FRAMES];
        let fog_sets_vec = dev
            .allocate_descriptor_sets(
                &vk::DescriptorSetAllocateInfo::default()
                    .descriptor_pool(desc_pool)
                    .set_layouts(&fog_layouts),
            )
            .unwrap();
        let fog_sets = [fog_sets_vec[0], fog_sets_vec[1]];

        for i in 0..MAX_FRAMES {
            let buf_info = vk::DescriptorBufferInfo::default()
                .buffer(fog_bufs[i])
                .range(size_of::<FogUbo>() as vk::DeviceSize);
            let write = vk::WriteDescriptorSet::default()
                .dst_set(fog_sets[i])
                .dst_binding(0)
                .descriptor_type(vk::DescriptorType::UNIFORM_BUFFER)
                .buffer_info(std::slice::from_ref(&buf_info));
            dev.update_descriptor_sets(&[write], &[]);
        }

        // Vertex buffer (host-visible, host-coherent) -----------------------
        let (vtx_buf, vtx_mem, vtx_raw) = create_buffer(
            &dev,
            &mem_props,
            VTX_BUF_BYTES,
            vk::BufferUsageFlags::VERTEX_BUFFER,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        );
        let vtx_ptr = vtx_raw as *mut Vertex;

        // Sampler -----------------------------------------------------------
        let sampler = dev
            .create_sampler(
                &vk::SamplerCreateInfo::default()
                    .mag_filter(vk::Filter::NEAREST)
                    .min_filter(vk::Filter::NEAREST)
                    .mipmap_mode(vk::SamplerMipmapMode::NEAREST)
                    .address_mode_u(vk::SamplerAddressMode::REPEAT)
                    .address_mode_v(vk::SamplerAddressMode::REPEAT)
                    .max_lod(0.0),
                None,
            )
            .unwrap();

        // Build the renderer, then create pipelines (need self's render_pass)
        let mut r = Box::new(Renderer {
            entry,
            instance,
            pdev,
            dev,
            q_family,
            queue,
            surface_ext,
            surface,
            swapchain_ext,
            swapchain,
            sc_images,
            sc_views,
            sc_format: sc_format.format,
            extent,
            depth_image,
            depth_mem,
            depth_view,
            depth_format,
            render_pass,
            framebuffers,
            cmd_pool,
            cmd_bufs,
            img_available,
            render_done,
            in_flight,
            desc_pool,
            fog_layout,
            tex_layout,
            pipe_layout,
            fog_bufs,
            fog_mems,
            fog_ptrs,
            fog_sets,
            vtx_buf,
            vtx_mem,
            vtx_ptr,
            vtx_head: 0,
            pipelines: [vk::Pipeline::null(); 5],
            sampler,
            textures: Vec::new(),
            chunks: Vec::new(),
            frame: 0,
            image_idx: 0,
            cur_cmd: vk::CommandBuffer::null(),
            clear_color: [0.0, 0.0, 0.0, 1.0],
            projection: Mat4::IDENTITY,
            modelview: Mat4::IDENTITY,
            mat_stack: Vec::new(),
            cur_pipeline: PIPE_OPAQUE,
            cur_tex: u32::MAX,

            fog: FogState::Off,
            fog_dirty: true,
            scissor_on: false,
            scissor: vk::Rect2D::default(),
        });

        r.pipelines = r.create_pipelines();

        // Default 1×1 white texture -----------------------------------------
        let white = [255u8; 4];
        r.texture_load_inner(white.as_ptr(), 1, 1);

        r
    }

    // -----------------------------------------------------------------------
    // Pipeline creation
    // -----------------------------------------------------------------------
    unsafe fn create_pipelines(&self) -> [vk::Pipeline; 5] {
        let entry = c"main";

        let vert_mod = make_shader_module(&self.dev, SPV_TERRAIN_VERT);
        let frag_mod = make_shader_module(&self.dev, SPV_TERRAIN_FRAG);
        let alpha_mod = make_shader_module(&self.dev, SPV_TERRAIN_ALPHA_FRAG);
        let gui_mod = make_shader_module(&self.dev, SPV_GUI_FRAG);

        let vert_stage = vk::PipelineShaderStageCreateInfo::default()
            .stage(vk::ShaderStageFlags::VERTEX)
            .module(vert_mod)
            .name(entry);

        // Vertex input (matches VertexDeclPTC / Vertex struct)
        let bindings = [vk::VertexInputBindingDescription::default()
            .binding(0)
            .stride(size_of::<Vertex>() as u32)
            .input_rate(vk::VertexInputRate::VERTEX)];
        let attribs = [
            vk::VertexInputAttributeDescription {
                binding: 0,
                location: 0,
                format: vk::Format::R32G32B32_SFLOAT,
                offset: 0,
            },
            vk::VertexInputAttributeDescription {
                binding: 0,
                location: 1,
                format: vk::Format::R32G32_SFLOAT,
                offset: 12,
            },
            vk::VertexInputAttributeDescription {
                binding: 0,
                location: 2,
                format: vk::Format::R8G8B8A8_UNORM,
                offset: 20,
            },
        ];
        let vertex_input = vk::PipelineVertexInputStateCreateInfo::default()
            .vertex_binding_descriptions(&bindings)
            .vertex_attribute_descriptions(&attribs);

        let input_assembly = vk::PipelineInputAssemblyStateCreateInfo::default()
            .topology(vk::PrimitiveTopology::TRIANGLE_LIST);

        // Viewport/scissor are dynamic
        let viewport_state = vk::PipelineViewportStateCreateInfo::default()
            .viewport_count(1)
            .scissor_count(1);

        let raster_base = vk::PipelineRasterizationStateCreateInfo::default()
            .polygon_mode(vk::PolygonMode::FILL)
            .line_width(1.0);

        let multisample = vk::PipelineMultisampleStateCreateInfo::default()
            .rasterization_samples(vk::SampleCountFlags::TYPE_1);

        let dynamic_states = [vk::DynamicState::VIEWPORT, vk::DynamicState::SCISSOR];
        let dynamic = vk::PipelineDynamicStateCreateInfo::default()
            .dynamic_states(&dynamic_states);

        // Helper: creates a pipeline with configurable blend/depth/cull
        let make_pipeline = |frag: vk::ShaderModule,
                             blend_enable: bool,
                             depth_write: bool,
                             depth_test: bool,
                             cull: vk::CullModeFlags|
         -> vk::Pipeline {
            let frag_stage = vk::PipelineShaderStageCreateInfo::default()
                .stage(vk::ShaderStageFlags::FRAGMENT)
                .module(frag)
                .name(entry);
            let stages = [vert_stage, frag_stage];

            let raster = raster_base.cull_mode(cull).front_face(vk::FrontFace::COUNTER_CLOCKWISE);

            let blend_att = if blend_enable {
                vk::PipelineColorBlendAttachmentState::default()
                    .blend_enable(true)
                    .src_color_blend_factor(vk::BlendFactor::SRC_ALPHA)
                    .dst_color_blend_factor(vk::BlendFactor::ONE_MINUS_SRC_ALPHA)
                    .color_blend_op(vk::BlendOp::ADD)
                    .src_alpha_blend_factor(vk::BlendFactor::ONE)
                    .dst_alpha_blend_factor(vk::BlendFactor::ZERO)
                    .alpha_blend_op(vk::BlendOp::ADD)
                    .color_write_mask(vk::ColorComponentFlags::RGBA)
            } else {
                vk::PipelineColorBlendAttachmentState::default()
                    .blend_enable(false)
                    .color_write_mask(vk::ColorComponentFlags::RGBA)
            };
            let blend = vk::PipelineColorBlendStateCreateInfo::default()
                .attachments(std::slice::from_ref(&blend_att));

            let depth_stencil = vk::PipelineDepthStencilStateCreateInfo::default()
                .depth_test_enable(depth_test)
                .depth_write_enable(depth_write)
                .depth_compare_op(vk::CompareOp::LESS_OR_EQUAL);

            let info = vk::GraphicsPipelineCreateInfo::default()
                .stages(&stages)
                .vertex_input_state(&vertex_input)
                .input_assembly_state(&input_assembly)
                .viewport_state(&viewport_state)
                .rasterization_state(&raster)
                .multisample_state(&multisample)
                .depth_stencil_state(&depth_stencil)
                .color_blend_state(&blend)
                .dynamic_state(&dynamic)
                .layout(self.pipe_layout)
                .render_pass(self.render_pass)
                .subpass(0);

            self.dev
                .create_graphics_pipelines(vk::PipelineCache::null(), &[info], None)
                .unwrap()[0]
        };

        let pipes = [
            // opaque
            make_pipeline(frag_mod, false, true, true, vk::CullModeFlags::BACK),
            // alpha_test
            make_pipeline(alpha_mod, false, true, true, vk::CullModeFlags::BACK),
            // transparent
            make_pipeline(frag_mod, true, false, true, vk::CullModeFlags::NONE),
            // gui
            make_pipeline(gui_mod, true, false, false, vk::CullModeFlags::NONE),
            // items
            make_pipeline(frag_mod, true, true, true, vk::CullModeFlags::BACK),
        ];

        self.dev.destroy_shader_module(vert_mod, None);
        self.dev.destroy_shader_module(frag_mod, None);
        self.dev.destroy_shader_module(alpha_mod, None);
        self.dev.destroy_shader_module(gui_mod, None);

        pipes
    }

    // -----------------------------------------------------------------------
    // Swapchain (re)creation
    // -----------------------------------------------------------------------
    unsafe fn destroy_swapchain(&mut self) {
        for &fb in &self.framebuffers {
            self.dev.destroy_framebuffer(fb, None);
        }
        self.framebuffers.clear();
        self.dev.destroy_image_view(self.depth_view, None);
        self.dev.free_memory(self.depth_mem, None);
        self.dev.destroy_image(self.depth_image, None);
        for &v in &self.sc_views {
            self.dev.destroy_image_view(v, None);
        }
        self.sc_views.clear();
        self.swapchain_ext.destroy_swapchain(self.swapchain, None);
    }

    unsafe fn rebuild_swapchain(&mut self, width: u32, height: u32) {
        self.dev.device_wait_idle().unwrap();
        self.destroy_swapchain();

        let mem_props = self
            .instance
            .get_physical_device_memory_properties(self.pdev);

        let caps = self
            .surface_ext
            .get_physical_device_surface_capabilities(self.pdev, self.surface)
            .unwrap();

        let extent = vk::Extent2D {
            width: width.clamp(caps.min_image_extent.width, caps.max_image_extent.width),
            height: height.clamp(caps.min_image_extent.height, caps.max_image_extent.height),
        };
        self.extent = extent;

        let img_count = (caps.min_image_count + 1).min(if caps.max_image_count == 0 {
            u32::MAX
        } else {
            caps.max_image_count
        });

        let present_modes = self
            .surface_ext
            .get_physical_device_surface_present_modes(self.pdev, self.surface)
            .unwrap();
        let present_mode = if present_modes.contains(&vk::PresentModeKHR::MAILBOX) {
            vk::PresentModeKHR::MAILBOX
        } else {
            vk::PresentModeKHR::FIFO
        };

        self.swapchain = self
            .swapchain_ext
            .create_swapchain(
                &vk::SwapchainCreateInfoKHR::default()
                    .surface(self.surface)
                    .min_image_count(img_count)
                    .image_format(self.sc_format)
                    .image_color_space(vk::ColorSpaceKHR::SRGB_NONLINEAR)
                    .image_extent(extent)
                    .image_array_layers(1)
                    .image_usage(vk::ImageUsageFlags::COLOR_ATTACHMENT)
                    .image_sharing_mode(vk::SharingMode::EXCLUSIVE)
                    .pre_transform(caps.current_transform)
                    .composite_alpha(vk::CompositeAlphaFlagsKHR::OPAQUE)
                    .present_mode(present_mode)
                    .clipped(true),
                None,
            )
            .unwrap();

        self.sc_images = self
            .swapchain_ext
            .get_swapchain_images(self.swapchain)
            .unwrap();
        self.sc_views = self
            .sc_images
            .iter()
            .map(|&img| {
                self.dev
                    .create_image_view(
                        &vk::ImageViewCreateInfo::default()
                            .image(img)
                            .view_type(vk::ImageViewType::TYPE_2D)
                            .format(self.sc_format)
                            .subresource_range(
                                vk::ImageSubresourceRange::default()
                                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                                    .level_count(1)
                                    .layer_count(1),
                            ),
                        None,
                    )
                    .unwrap()
            })
            .collect();

        let depth_aspect = if self.depth_format == vk::Format::D32_SFLOAT {
            vk::ImageAspectFlags::DEPTH
        } else {
            vk::ImageAspectFlags::DEPTH | vk::ImageAspectFlags::STENCIL
        };
        let (depth_image, depth_mem) = create_image_2d(
            &self.dev,
            &mem_props,
            extent.width,
            extent.height,
            self.depth_format,
            vk::ImageUsageFlags::DEPTH_STENCIL_ATTACHMENT,
            vk::ImageTiling::OPTIMAL,
            vk::MemoryPropertyFlags::DEVICE_LOCAL,
        );
        self.depth_image = depth_image;
        self.depth_mem = depth_mem;
        self.depth_view = self
            .dev
            .create_image_view(
                &vk::ImageViewCreateInfo::default()
                    .image(depth_image)
                    .view_type(vk::ImageViewType::TYPE_2D)
                    .format(self.depth_format)
                    .subresource_range(
                        vk::ImageSubresourceRange::default()
                            .aspect_mask(depth_aspect)
                            .level_count(1)
                            .layer_count(1),
                    ),
                None,
            )
            .unwrap();

        self.framebuffers = self
            .sc_views
            .iter()
            .map(|&view| {
                let atts = [view, self.depth_view];
                self.dev
                    .create_framebuffer(
                        &vk::FramebufferCreateInfo::default()
                            .render_pass(self.render_pass)
                            .attachments(&atts)
                            .width(extent.width)
                            .height(extent.height)
                            .layers(1),
                        None,
                    )
                    .unwrap()
            })
            .collect();
    }

    // -----------------------------------------------------------------------
    // Upload fog UBO for the current frame
    // -----------------------------------------------------------------------
    unsafe fn flush_fog(&mut self) {
        if !self.fog_dirty {
            return;
        }
        let ubo = match &self.fog {
            FogState::Off => FogUbo {
                color: [0.0; 4],
                start: 0.0,
                end: 0.0,
                density: 0.0,
                mode: 0,
            },
            FogState::Linear { start, end, r, g, b } => FogUbo {
                color: [*r, *g, *b, 1.0],
                start: *start,
                end: *end,
                density: 0.0,
                mode: 1,
            },
            FogState::Exp { density, r, g, b } => FogUbo {
                color: [*r, *g, *b, 1.0],
                start: 0.0,
                end: 0.0,
                density: *density,
                mode: 2,
            },
        };
        self.fog_ptrs[self.frame].write(ubo);
        self.fog_dirty = false;
    }

    // -----------------------------------------------------------------------
    // Internal texture upload helper
    // -----------------------------------------------------------------------
    unsafe fn texture_load_inner(&mut self, data: *const u8, width: u32, height: u32) -> u32 {
        let mem_props = self
            .instance
            .get_physical_device_memory_properties(self.pdev);

        // Staging buffer
        let byte_size = (width * height * 4) as vk::DeviceSize;
        let (staging, staging_mem, staging_ptr) = create_buffer(
            &self.dev,
            &mem_props,
            byte_size,
            vk::BufferUsageFlags::TRANSFER_SRC,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        );
        std::ptr::copy_nonoverlapping(data, staging_ptr, byte_size as usize);

        // Device image
        let (image, img_mem) = create_image_2d(
            &self.dev,
            &mem_props,
            width,
            height,
            vk::Format::R8G8B8A8_UNORM,
            vk::ImageUsageFlags::TRANSFER_DST | vk::ImageUsageFlags::SAMPLED,
            vk::ImageTiling::OPTIMAL,
            vk::MemoryPropertyFlags::DEVICE_LOCAL,
        );

        // Copy via one-shot command buffer
        let cb = one_shot_begin(&self.dev, self.cmd_pool);

        image_barrier(
            &self.dev,
            cb,
            image,
            vk::ImageAspectFlags::COLOR,
            vk::ImageLayout::UNDEFINED,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            vk::PipelineStageFlags::TOP_OF_PIPE,
            vk::PipelineStageFlags::TRANSFER,
            vk::AccessFlags::empty(),
            vk::AccessFlags::TRANSFER_WRITE,
        );

        let copy = vk::BufferImageCopy::default()
            .image_subresource(
                vk::ImageSubresourceLayers::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .layer_count(1),
            )
            .image_extent(vk::Extent3D {
                width,
                height,
                depth: 1,
            });
        self.dev
            .cmd_copy_buffer_to_image(cb, staging, image, vk::ImageLayout::TRANSFER_DST_OPTIMAL, &[copy]);

        image_barrier(
            &self.dev,
            cb,
            image,
            vk::ImageAspectFlags::COLOR,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL,
            vk::PipelineStageFlags::TRANSFER,
            vk::PipelineStageFlags::FRAGMENT_SHADER,
            vk::AccessFlags::TRANSFER_WRITE,
            vk::AccessFlags::SHADER_READ,
        );

        one_shot_end(&self.dev, self.cmd_pool, self.queue, cb);
        self.dev.destroy_buffer(staging, None);
        self.dev.free_memory(staging_mem, None);

        // Image view
        let view = self
            .dev
            .create_image_view(
                &vk::ImageViewCreateInfo::default()
                    .image(image)
                    .view_type(vk::ImageViewType::TYPE_2D)
                    .format(vk::Format::R8G8B8A8_UNORM)
                    .subresource_range(
                        vk::ImageSubresourceRange::default()
                            .aspect_mask(vk::ImageAspectFlags::COLOR)
                            .level_count(1)
                            .layer_count(1),
                    ),
                None,
            )
            .unwrap();

        // Descriptor set for this texture
        let layouts = [self.tex_layout];
        let desc_set = self
            .dev
            .allocate_descriptor_sets(
                &vk::DescriptorSetAllocateInfo::default()
                    .descriptor_pool(self.desc_pool)
                    .set_layouts(&layouts),
            )
            .unwrap()[0];

        let img_info = vk::DescriptorImageInfo::default()
            .image_layout(vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL)
            .image_view(view)
            .sampler(self.sampler);
        let write = vk::WriteDescriptorSet::default()
            .dst_set(desc_set)
            .dst_binding(0)
            .descriptor_type(vk::DescriptorType::COMBINED_IMAGE_SAMPLER)
            .image_info(std::slice::from_ref(&img_info));
        self.dev.update_descriptor_sets(&[write], &[]);

        let id = self.textures.len() as u32;
        self.textures.push(TextureEntry {
            image,
            memory: img_mem,
            view,
            desc_set,
        });
        id
    }

    // -----------------------------------------------------------------------
    // Record a draw call using the current render state.
    // `first` and `count` are indices into the frame vertex buffer.
    // -----------------------------------------------------------------------
    unsafe fn issue_draw(&mut self, first: u32, count: u32) {
        if count == 0 {
            return;
        }

        self.flush_fog();

        let mvp = self.projection * self.modelview;
        let mvp_bytes =
            std::slice::from_raw_parts(mvp.as_ref() as *const _ as *const u8, 64);
        self.dev.cmd_push_constants(
            self.cur_cmd,
            self.pipe_layout,
            vk::ShaderStageFlags::VERTEX,
            0,
            mvp_bytes,
        );

        let fog_set = self.fog_sets[self.frame];
        let tex_set = if (self.cur_tex as usize) < self.textures.len() {
            self.textures[self.cur_tex as usize].desc_set
        } else {
            self.textures[0].desc_set
        };
        self.dev.cmd_bind_descriptor_sets(
            self.cur_cmd,
            vk::PipelineBindPoint::GRAPHICS,
            self.pipe_layout,
            0,
            &[fog_set, tex_set],
            &[],
        );

        self.dev.cmd_draw(self.cur_cmd, count, 1, first, 0);
    }

    // -----------------------------------------------------------------------
    // Draw from an arbitrary vertex buffer (for chunk draws)
    // -----------------------------------------------------------------------
    unsafe fn issue_draw_from(&mut self, buffer: vk::Buffer, count: u32) {
        if count == 0 {
            return;
        }
        self.dev
            .cmd_bind_vertex_buffers(self.cur_cmd, 0, &[buffer], &[0]);
        self.issue_draw(0, count);
        // Restore the frame ring buffer so subsequent vk_commit calls work
        self.dev
            .cmd_bind_vertex_buffers(self.cur_cmd, 0, &[self.vtx_buf], &[0]);
    }

    // -----------------------------------------------------------------------
    // Clear depth attachment mid-render-pass
    // -----------------------------------------------------------------------
    unsafe fn clear_depth(&self) {
        let att = vk::ClearAttachment::default()
            .aspect_mask(vk::ImageAspectFlags::DEPTH)
            .clear_value(vk::ClearValue {
                depth_stencil: vk::ClearDepthStencilValue {
                    depth: 1.0,
                    stencil: 0,
                },
            });
        let rect = vk::ClearRect {
            rect: vk::Rect2D {
                offset: vk::Offset2D { x: 0, y: 0 },
                extent: self.extent,
            },
            base_array_layer: 0,
            layer_count: 1,
        };
        self.dev.cmd_clear_attachments(self.cur_cmd, &[att], &[rect]);
    }

    // -----------------------------------------------------------------------
    // Bind a different pipeline
    // -----------------------------------------------------------------------
    unsafe fn switch_pipeline(&mut self, pipe: usize) {
        self.cur_pipeline = pipe;
        self.dev.cmd_bind_pipeline(
            self.cur_cmd,
            vk::PipelineBindPoint::GRAPHICS,
            self.pipelines[pipe],
        );
    }
}

// ---------------------------------------------------------------------------
// Shutdown helper
// ---------------------------------------------------------------------------
unsafe fn shutdown_renderer(r: &mut Renderer) {
    r.dev.device_wait_idle().unwrap();

    for te in &r.textures {
        r.dev.destroy_image_view(te.view, None);
        r.dev.free_memory(te.memory, None);
        r.dev.destroy_image(te.image, None);
    }
    r.dev.destroy_sampler(r.sampler, None);

    for slot in r.chunks.iter().flatten() {
        r.dev.destroy_buffer(slot.0, None);
        r.dev.free_memory(slot.1, None);
    }

    r.dev.destroy_buffer(r.vtx_buf, None);
    r.dev.free_memory(r.vtx_mem, None);

    for i in 0..MAX_FRAMES {
        r.dev.destroy_buffer(r.fog_bufs[i], None);
        r.dev.free_memory(r.fog_mems[i], None);
        r.dev.destroy_semaphore(r.img_available[i], None);
        r.dev.destroy_semaphore(r.render_done[i], None);
        r.dev.destroy_fence(r.in_flight[i], None);
    }

    r.dev.destroy_descriptor_pool(r.desc_pool, None);
    r.dev.destroy_descriptor_set_layout(r.fog_layout, None);
    r.dev.destroy_descriptor_set_layout(r.tex_layout, None);
    r.dev.destroy_pipeline_layout(r.pipe_layout, None);

    for &p in &r.pipelines {
        r.dev.destroy_pipeline(p, None);
    }

    r.dev.destroy_command_pool(r.cmd_pool, None);

    r.destroy_swapchain();
    r.dev.destroy_render_pass(r.render_pass, None);

    r.dev.destroy_device(None);
    r.surface_ext.destroy_surface(r.surface, None);
    r.instance.destroy_instance(None);
}

// ===========================================================================
// FFI exports
// ===========================================================================

#[unsafe(no_mangle)]
pub extern "C" fn vk_init(sdl_window: *mut c_void, width: u32, height: u32) -> c_int {
    unsafe {
        RENDERER = Some(Renderer::new(sdl_window, width, height));
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_shutdown() {
    unsafe {
        let p = std::ptr::addr_of_mut!(RENDERER);
        if let Some(mut b) = (*p).take() {
            shutdown_renderer(&mut b);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_resize(width: u32, height: u32) {
    unsafe { r().rebuild_swapchain(width, height) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_begin_frame() -> c_int {
    let rd = r();
    unsafe {
        // Wait for this slot's fence
        rd.dev
            .wait_for_fences(&[rd.in_flight[rd.frame]], true, u64::MAX)
            .unwrap();
        rd.dev.reset_fences(&[rd.in_flight[rd.frame]]).unwrap();

        // Acquire next image
        let (idx, suboptimal) = match rd
            .swapchain_ext
            .acquire_next_image(
                rd.swapchain,
                u64::MAX,
                rd.img_available[rd.frame],
                vk::Fence::null(),
            ) {
            Ok(v) => v,
            Err(vk::Result::ERROR_OUT_OF_DATE_KHR) => {
                let e = rd.extent;
                rd.rebuild_swapchain(e.width, e.height);
                return -1;
            }
            Err(e) => panic!("acquire_next_image: {e}"),
        };
        if suboptimal {
            let e = rd.extent;
            // will be rebuilt next frame
            let _ = (e.width, e.height);
        }
        rd.image_idx = idx;

        let cmd = rd.cmd_bufs[rd.frame];
        rd.cur_cmd = cmd;
        rd.dev
            .reset_command_buffer(cmd, vk::CommandBufferResetFlags::empty())
            .unwrap();
        rd.dev
            .begin_command_buffer(
                cmd,
                &vk::CommandBufferBeginInfo::default()
                    .flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT),
            )
            .unwrap();

        // Begin render pass
        let clear_vals = [
            vk::ClearValue {
                color: vk::ClearColorValue {
                    float32: rd.clear_color,
                },
            },
            vk::ClearValue {
                depth_stencil: vk::ClearDepthStencilValue {
                    depth: 1.0,
                    stencil: 0,
                },
            },
        ];
        rd.dev.cmd_begin_render_pass(
            cmd,
            &vk::RenderPassBeginInfo::default()
                .render_pass(rd.render_pass)
                .framebuffer(rd.framebuffers[idx as usize])
                .render_area(vk::Rect2D {
                    offset: vk::Offset2D { x: 0, y: 0 },
                    extent: rd.extent,
                })
                .clear_values(&clear_vals),
            vk::SubpassContents::INLINE,
        );

        // Viewport with negative height → Y-flip (Vulkan 1.1 core)
        let viewport = vk::Viewport {
            x: 0.0,
            y: rd.extent.height as f32,
            width: rd.extent.width as f32,
            height: -(rd.extent.height as f32),
            min_depth: 0.0,
            max_depth: 1.0,
        };
        rd.dev.cmd_set_viewport(cmd, 0, &[viewport]);

        let scissor = vk::Rect2D {
            offset: vk::Offset2D { x: 0, y: 0 },
            extent: rd.extent,
        };
        rd.dev.cmd_set_scissor(cmd, 0, &[scissor]);

        // Bind vertex buffer (offset=0; firstVertex in cmd_draw carries offset)
        rd.dev
            .cmd_bind_vertex_buffers(cmd, 0, &[rd.vtx_buf], &[0]);

        // Reset dynamic vertex head
        rd.vtx_head = 0;

        // Bind default pipeline
        rd.dev.cmd_bind_pipeline(
            cmd,
            vk::PipelineBindPoint::GRAPHICS,
            rd.pipelines[rd.cur_pipeline],
        );

        // Ensure fog UBO is fresh
        rd.fog_dirty = true;
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_end_frame() {
    let rd = r();
    unsafe {
        rd.dev.cmd_end_render_pass(rd.cur_cmd);
        rd.dev.end_command_buffer(rd.cur_cmd).unwrap();

        let wait_sems = [rd.img_available[rd.frame]];
        let wait_stages = [vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT];
        let signal_sems = [rd.render_done[rd.frame]];
        let cmds = [rd.cur_cmd];
        let submit = vk::SubmitInfo::default()
            .wait_semaphores(&wait_sems)
            .wait_dst_stage_mask(&wait_stages)
            .command_buffers(&cmds)
            .signal_semaphores(&signal_sems);
        rd.dev
            .queue_submit(rd.queue, &[submit], rd.in_flight[rd.frame])
            .unwrap();

        let swapchains = [rd.swapchain];
        let indices = [rd.image_idx];
        let present_info = vk::PresentInfoKHR::default()
            .wait_semaphores(&signal_sems)
            .swapchains(&swapchains)
            .image_indices(&indices);
        match rd.swapchain_ext.queue_present(rd.queue, &present_info) {
            Ok(_) => {}
            Err(vk::Result::ERROR_OUT_OF_DATE_KHR) | Err(vk::Result::SUBOPTIMAL_KHR) => {
                let e = rd.extent;
                rd.rebuild_swapchain(e.width, e.height);
            }
            Err(e) => panic!("queue_present: {e}"),
        }

        rd.frame = (rd.frame + 1) % MAX_FRAMES;
        rd.cur_cmd = vk::CommandBuffer::null();
    }
}

// ---------------------------------------------------------------------------
// Clear colour
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_set_clear_color(red: f32, green: f32, blue: f32, alpha: f32) {
    r().clear_color = [red, green, blue, alpha];
}

// ---------------------------------------------------------------------------
// Scissor
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_set_scissor(x: i32, y: i32, w: u32, h: u32, enable: c_int) {
    let rd = r();
    rd.scissor_on = enable != 0;
    let rect = if enable != 0 {
        vk::Rect2D {
            offset: vk::Offset2D { x, y },
            extent: vk::Extent2D {
                width: w,
                height: h,
            },
        }
    } else {
        vk::Rect2D {
            offset: vk::Offset2D { x: 0, y: 0 },
            extent: rd.extent,
        }
    };
    rd.scissor = rect;
    if rd.cur_cmd != vk::CommandBuffer::null() {
        unsafe { rd.dev.cmd_set_scissor(rd.cur_cmd, 0, &[rect]) };
    }
}

// ---------------------------------------------------------------------------
// Projection
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_projection_perspective(fov: f32, aspect: f32, near: f32, far: f32) {
    // glam::Mat4::perspective_rh: right-handed, Z in [0,1], Y-up
    // Combined with the negative-height viewport, this matches OpenGL conventions.
    r().projection = Mat4::perspective_rh(fov.to_radians(), aspect, near, far);
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_projection_ortho(l: f32, rr: f32, b: f32, t: f32, n: f32, f: f32) {
    // Build an OpenGL-style ortho matrix mapping to Vulkan clip space [0,1] in Z.
    // l..r → [-1,1], b..t → [-1,1] (Y-up, handled by negative viewport),
    // -n..-f in view space → [0,1] in NDC-Z.
    let inv_rl = 1.0 / (rr - l);
    let inv_tb = 1.0 / (t - b);
    let inv_fn = 1.0 / (n - f); // n < f so this is negative
    r().projection = Mat4::from_cols_array_2d(&[
        [2.0 * inv_rl,         0.0,          0.0,        0.0],
        [0.0,          2.0 * inv_tb,          0.0,        0.0],
        [0.0,                  0.0,         inv_fn,        0.0],
        [-(rr + l) * inv_rl, -(t + b) * inv_tb, n * inv_fn, 1.0],
    ]);
}

// ---------------------------------------------------------------------------
// Matrix stack
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_push_matrix() {
    let rd = r();
    rd.mat_stack.push(rd.modelview);
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_pop_matrix() {
    let rd = r();
    rd.modelview = rd.mat_stack.pop().expect("matrix stack underflow");
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_load_identity() {
    r().modelview = Mat4::IDENTITY;
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_translate(x: f32, y: f32, z: f32) {
    let mv = r().modelview;
    r().modelview = mv * Mat4::from_translation(glam::Vec3::new(x, y, z));
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_rotate(angle_deg: f32, x: f32, y: f32, z: f32) {
    let axis = glam::Vec3::new(x, y, z);
    if axis.length_squared() < 1e-9 {
        return;
    }
    let mv = r().modelview;
    r().modelview = mv * Mat4::from_axis_angle(axis.normalize(), angle_deg.to_radians());
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_scale(x: f32, y: f32, z: f32) {
    let mv = r().modelview;
    r().modelview = mv * Mat4::from_scale(glam::Vec3::new(x, y, z));
}

// ---------------------------------------------------------------------------
// Fog
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_fog_linear(start: f32, end: f32, red: f32, green: f32, blue: f32) {
    let rd = r();
    rd.fog = FogState::Linear {
        start,
        end,
        r: red,
        g: green,
        b: blue,
    };
    rd.fog_dirty = true;
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_fog_exp(density: f32, red: f32, green: f32, blue: f32) {
    let rd = r();
    rd.fog = FogState::Exp {
        density,
        r: red,
        g: green,
        b: blue,
    };
    rd.fog_dirty = true;
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_fog_off() {
    let rd = r();
    rd.fog = FogState::Off;
    rd.fog_dirty = true;
}

// ---------------------------------------------------------------------------
// Textures
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_texture_load(
    data: *const u8,
    width: u32,
    height: u32,
    _has_alpha: c_int,
) -> u32 {
    unsafe { r().texture_load_inner(data, width, height) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_texture_bind(id: u32) {
    r().cur_tex = id;
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_texture_update_sub(
    id: u32,
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    data: *const u8,
) {
    let rd = r();
    if id as usize >= rd.textures.len() {
        return;
    }
    unsafe {
        let mem_props = rd.instance.get_physical_device_memory_properties(rd.pdev);
        let byte_size = (w * h * 4) as vk::DeviceSize;
        let (staging, staging_mem, staging_ptr) = create_buffer(
            &rd.dev,
            &mem_props,
            byte_size,
            vk::BufferUsageFlags::TRANSFER_SRC,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        );
        std::ptr::copy_nonoverlapping(data, staging_ptr, byte_size as usize);

        let cb = one_shot_begin(&rd.dev, rd.cmd_pool);
        image_barrier(
            &rd.dev,
            cb,
            rd.textures[id as usize].image,
            vk::ImageAspectFlags::COLOR,
            vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            vk::PipelineStageFlags::FRAGMENT_SHADER,
            vk::PipelineStageFlags::TRANSFER,
            vk::AccessFlags::SHADER_READ,
            vk::AccessFlags::TRANSFER_WRITE,
        );
        let copy = vk::BufferImageCopy::default()
            .image_subresource(
                vk::ImageSubresourceLayers::default()
                    .aspect_mask(vk::ImageAspectFlags::COLOR)
                    .layer_count(1),
            )
            .image_offset(vk::Offset3D {
                x: x as i32,
                y: y as i32,
                z: 0,
            })
            .image_extent(vk::Extent3D {
                width: w,
                height: h,
                depth: 1,
            });
        rd.dev.cmd_copy_buffer_to_image(
            cb,
            staging,
            rd.textures[id as usize].image,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            &[copy],
        );
        image_barrier(
            &rd.dev,
            cb,
            rd.textures[id as usize].image,
            vk::ImageAspectFlags::COLOR,
            vk::ImageLayout::TRANSFER_DST_OPTIMAL,
            vk::ImageLayout::SHADER_READ_ONLY_OPTIMAL,
            vk::PipelineStageFlags::TRANSFER,
            vk::PipelineStageFlags::FRAGMENT_SHADER,
            vk::AccessFlags::TRANSFER_WRITE,
            vk::AccessFlags::SHADER_READ,
        );
        one_shot_end(&rd.dev, rd.cmd_pool, rd.queue, cb);
        rd.dev.destroy_buffer(staging, None);
        rd.dev.free_memory(staging_mem, None);
    }
}

// ---------------------------------------------------------------------------
// Vertex submission
// ---------------------------------------------------------------------------

/// Reserve `count` vertices in the frame's persistently-mapped GPU vertex buffer.
/// The caller writes VertexDeclPTC-layout structs (24 bytes each) into the returned
/// pointer, then calls vk_commit(count) to record the draw call.
/// Returns NULL if the frame buffer is full.
#[unsafe(no_mangle)]
pub extern "C" fn vk_reserve_verts(count: u32) -> *mut c_void {
    let rd = r();
    let head = rd.vtx_head;
    if head + count as usize > MAX_VERTS {
        return std::ptr::null_mut();
    }
    // Return the pointer at the current write head; vk_commit advances it.
    unsafe { rd.vtx_ptr.add(head) as *mut c_void }
}

/// Submit a draw call for the `count` vertices just written via vk_reserve_verts().
/// Captures the current texture, fog, pipeline, and matrix state.
#[unsafe(no_mangle)]
pub extern "C" fn vk_commit(count: u32) {
    let rd = r();
    let first = rd.vtx_head as u32;
    rd.vtx_head += count as usize;
    unsafe { rd.issue_draw(first, count) };
}

/// Copy `count` pre-built vertices from `data` into the frame buffer and draw.
/// Layout: 3×f32 pos, 2×f32 uv, u32 ABGR color (24 bytes per vertex).
#[unsafe(no_mangle)]
pub extern "C" fn vk_draw_verts(data: *const c_void, count: u32) {
    let rd = r();
    let first = rd.vtx_head;
    assert!(
        first + count as usize <= MAX_VERTS,
        "vk: frame vertex buffer full — increase VTX_BUF_BYTES"
    );
    unsafe {
        rd.vtx_ptr
            .add(first)
            .copy_from_nonoverlapping(data as *const Vertex, count as usize);
    }
    rd.vtx_head += count as usize;
    unsafe { rd.issue_draw(first as u32, count) };
}

// ---------------------------------------------------------------------------
// Render passes
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_pass_opaque() {
    unsafe { r().switch_pipeline(PIPE_OPAQUE) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_pass_alpha_test() {
    unsafe { r().switch_pipeline(PIPE_ALPHA) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_pass_transparent() {
    unsafe { r().switch_pipeline(PIPE_TRANSPARENT) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_pass_gui() {
    let rd = r();
    unsafe { rd.clear_depth() }
    rd.fog = FogState::Off;
    rd.fog_dirty = true;
    unsafe { rd.switch_pipeline(PIPE_GUI) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_pass_items() {
    let rd = r();
    unsafe {
        rd.clear_depth();
        rd.switch_pipeline(PIPE_ITEMS);
    }
}

// ---------------------------------------------------------------------------
// Chunk (persistent vertex) buffers
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_chunk_set(id: u32, data: *const c_void, count: u32) {
    if id == 0 || count == 0 {
        return;
    }
    let rd = r();
    let idx = id as usize;
    unsafe {
        let mem_props = rd.instance.get_physical_device_memory_properties(rd.pdev);
        // Destroy previous buffer at this slot if present
        if idx < rd.chunks.len() {
            if let Some((old_buf, old_mem)) = rd.chunks[idx].take() {
                rd.dev.destroy_buffer(old_buf, None);
                rd.dev.free_memory(old_mem, None);
            }
        }
        // Grow the slot vec as needed
        if idx >= rd.chunks.len() {
            rd.chunks.resize_with(idx + 1, || None);
        }
        let byte_size = (count as vk::DeviceSize) * size_of::<Vertex>() as vk::DeviceSize;
        let (buf, mem, ptr) = create_buffer(
            &rd.dev,
            &mem_props,
            byte_size,
            vk::BufferUsageFlags::VERTEX_BUFFER,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        );
        std::ptr::copy_nonoverlapping(data as *const u8, ptr, byte_size as usize);
        rd.chunks[idx] = Some((buf, mem));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_chunk_draw(id: u32, count: u32) {
    if id == 0 || count == 0 {
        return;
    }
    let rd = r();
    let idx = id as usize;
    if idx >= rd.chunks.len() {
        return;
    }
    if let Some((buf, _)) = rd.chunks[idx] {
        unsafe { rd.issue_draw_from(buf, count) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_chunk_free(id: u32) {
    if id == 0 {
        return;
    }
    let rd = r();
    let idx = id as usize;
    if idx >= rd.chunks.len() {
        return;
    }
    if let Some((buf, mem)) = rd.chunks[idx].take() {
        unsafe {
            rd.dev.destroy_buffer(buf, None);
            rd.dev.free_memory(mem, None);
        }
    }
}

// ---------------------------------------------------------------------------
// Matrix read-back for frustum culling
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn vk_get_projection_matrix(out: *mut f32) {
    let m = r().projection;
    unsafe { std::ptr::copy_nonoverlapping(m.as_ref().as_ptr(), out, 16) };
}

#[unsafe(no_mangle)]
pub extern "C" fn vk_get_modelview_matrix(out: *mut f32) {
    let m = r().modelview;
    unsafe { std::ptr::copy_nonoverlapping(m.as_ref().as_ptr(), out, 16) };
}
