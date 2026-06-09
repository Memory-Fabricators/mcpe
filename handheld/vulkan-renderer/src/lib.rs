// vulkan_renderer/src/lib.rs — extern "C" API using ash Vulkan bindings.

use std::os::raw::c_void;

mod instance;
mod device;
mod swapchain;
mod pipeline;
mod commands;
mod buffers;
mod draw;
mod shaders;

/// Opaque handle returned to C++.
#[repr(C)]
pub struct VulkanRenderer {
    _private: [u8; 0],
}

/// Internal state.
struct Renderer {
    window: *mut c_void,
    instance: instance::InstanceCtx,
    device: device::DeviceCtx,
    swapchain: swapchain::Swapchain,
    pipeline: pipeline::Pipeline,
    cmd: commands::CommandContext,
    buffers: buffers::BufferManager,
    current_frame: u64,
}

// ---- extern "C" API ----

#[unsafe(no_mangle)]
pub extern "C" fn vulkan_renderer_new(window: *mut c_void) -> *mut VulkanRenderer {
    let r = match init_renderer(window) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("vulkan_renderer_new: {e}");
            return std::ptr::null_mut();
        }
    };
    Box::into_raw(Box::new(r)) as *mut VulkanRenderer
}

#[unsafe(no_mangle)]
pub extern "C" fn vulkan_renderer_destroy(ptr: *mut VulkanRenderer) {
    if ptr.is_null() { return; }
    unsafe {
        let _r = Box::from_raw(ptr as *mut Renderer);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vulkan_renderer_draw_frame(ptr: *mut VulkanRenderer) {
    if ptr.is_null() { return; }
    unsafe {
        let r = &mut *(ptr as *mut Renderer);
        if let Err(e) = draw::draw_frame(r) {
            eprintln!("draw_frame: {e}");
        }
    }
}

// ---- internal init ----

fn init_renderer(window: *mut c_void) -> Result<Renderer, String> {
    let inst = instance::create()?;
    let dev = device::select(&inst, window)?;
    let sw = swapchain::create(&inst, &dev, window)?;
    let pipe = pipeline::create(&dev, &sw)?;
    let cmd = commands::create(&dev, sw.image_count)?;
    let bufs = buffers::create(&inst, &dev)?;

    Ok(Renderer {
        window,
        instance: inst,
        device: dev,
        swapchain: sw,
        pipeline: pipe,
        cmd,
        buffers: bufs,
        current_frame: 0,
    })
}
