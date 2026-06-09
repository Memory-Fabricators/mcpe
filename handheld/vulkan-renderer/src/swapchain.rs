// vulkan_renderer/src/swapchain.rs — swapchain via ash.

use crate::instance::InstanceCtx;
use crate::device::DeviceCtx;
use ash::vk;

pub struct Swapchain {
    pub handle: vk::SwapchainKHR,
    pub surface: vk::SurfaceKHR,
    pub images: Vec<vk::Image>,
    pub image_views: Vec<vk::ImageView>,
    pub framebuffers: Vec<vk::Framebuffer>,
    pub format: vk::Format,
    pub extent: vk::Extent2D,
    pub image_count: u32,
}

pub fn create(instance: &InstanceCtx, device: &DeviceCtx, window: *mut std::ffi::c_void) -> Result<Swapchain, String> {
    unsafe {
        let surface = create_surface(instance, window)?;
        let format = choose_surface_format(instance, device, surface)?;

        let caps = instance
            .surface_ext
            .get_physical_device_surface_capabilities(device.physical, surface)
            .map_err(|e| format!("get_physical_device_surface_capabilities: {e}"))?;

        let extent = choose_extent(&caps);

        let present_mode = vk::PresentModeKHR::FIFO;

        let mut image_count = caps.min_image_count + 1;
        if caps.max_image_count > 0 && image_count > caps.max_image_count {
            image_count = caps.max_image_count;
        }
        if image_count < 3 {
            image_count = 3.min(caps.max_image_count.max(caps.min_image_count));
        }

        let mut create_info = vk::SwapchainCreateInfoKHR::default()
            .surface(surface)
            .min_image_count(image_count)
            .image_format(format.format)
            .image_color_space(format.color_space)
            .image_extent(extent)
            .image_array_layers(1)
            .image_usage(vk::ImageUsageFlags::COLOR_ATTACHMENT)
            .pre_transform(caps.current_transform)
            .composite_alpha(vk::CompositeAlphaFlagsKHR::OPAQUE)
            .present_mode(present_mode)
            .clipped(true);

        let families;
        if device.graphics_family != device.present_family {
            families = [device.graphics_family, device.present_family];
            create_info = create_info
                .image_sharing_mode(vk::SharingMode::CONCURRENT)
                .queue_family_indices(&families);
        }

        let swapchain = device
            .swapchain_ext
            .create_swapchain(&create_info, None)
            .map_err(|e| {
                instance.surface_ext.destroy_surface(surface, None);
                format!("vkCreateSwapchainKHR failed: {e}")
            })?;

        let images = device
            .swapchain_ext
            .get_swapchain_images(swapchain)
            .map_err(|e| format!("vkGetSwapchainImagesKHR failed: {e}"))?;

        let image_count = images.len() as u32;
        let image_views = create_image_views(device, &images, format.format)?;

        Ok(Swapchain {
            handle: swapchain,
            surface,
            images,
            image_views,
            framebuffers: vec![],
            format: format.format,
            extent,
            image_count,
        })
    }
}

pub fn create_framebuffers(device: &DeviceCtx, swapchain: &mut Swapchain, render_pass: vk::RenderPass) -> Result<(), String> {
    unsafe {
        for &fb in &swapchain.framebuffers {
            device.inner.destroy_framebuffer(fb, None);
        }
        swapchain.framebuffers.clear();

        for &view in &swapchain.image_views {
            let attachments = [view];
            let create_info = vk::FramebufferCreateInfo::default()
                .render_pass(render_pass)
                .attachments(&attachments)
                .width(swapchain.extent.width)
                .height(swapchain.extent.height)
                .layers(1);

            let fb = device
                .inner
                .create_framebuffer(&create_info, None)
                .map_err(|e| format!("vkCreateFramebuffer failed: {e}"))?;
            swapchain.framebuffers.push(fb);
        }
        Ok(())
    }
}

unsafe fn create_surface(instance: &InstanceCtx, _window: *mut std::ffi::c_void) -> Result<vk::SurfaceKHR, String> {
    unsafe extern "C" {
        fn sdl_vulkan_create_surface(window: *mut std::ffi::c_void, instance: vk::Instance) -> vk::SurfaceKHR;
    }
    let surface = sdl_vulkan_create_surface(_window, instance.inner.handle());
    if surface == vk::SurfaceKHR::null() {
        return Err("SDL_Vulkan_CreateSurface returned null".into());
    }
    Ok(surface)
}

unsafe fn choose_surface_format(
    instance: &InstanceCtx,
    device: &DeviceCtx,
    surface: vk::SurfaceKHR,
) -> Result<vk::SurfaceFormatKHR, String> {
    let formats = instance
        .surface_ext
        .get_physical_device_surface_formats(device.physical, surface)
        .map_err(|e| format!("get_physical_device_surface_formats: {e}"))?;

    for fmt in &formats {
        if fmt.format == vk::Format::B8G8R8A8_SRGB
            && fmt.color_space == vk::ColorSpaceKHR::SRGB_NONLINEAR
        {
            return Ok(*fmt);
        }
    }
    if formats.is_empty() {
        Err("No surface formats available".into())
    } else {
        Ok(formats[0])
    }
}

unsafe fn choose_extent(caps: &vk::SurfaceCapabilitiesKHR) -> vk::Extent2D {
    if caps.current_extent.width != u32::MAX {
        caps.current_extent
    } else {
        vk::Extent2D {
            width: 800_u32.clamp(caps.min_image_extent.width, caps.max_image_extent.width),
            height: 600_u32.clamp(caps.min_image_extent.height, caps.max_image_extent.height),
        }
    }
}

unsafe fn create_image_views(device: &DeviceCtx, images: &[vk::Image], format: vk::Format) -> Result<Vec<vk::ImageView>, String> {
    let mut views = vec![];
    for &image in images {
        let create_info = vk::ImageViewCreateInfo::default()
            .image(image)
            .view_type(vk::ImageViewType::TYPE_2D)
            .format(format)
            .subresource_range(vk::ImageSubresourceRange {
                aspect_mask: vk::ImageAspectFlags::COLOR,
                base_mip_level: 0,
                level_count: 1,
                base_array_layer: 0,
                layer_count: 1,
                ..Default::default()
            });

        let view = device
            .inner
            .create_image_view(&create_info, None)
            .map_err(|e| format!("vkCreateImageView failed: {e}"))?;
        views.push(view);
    }
    Ok(views)
}

impl Drop for Swapchain {
    fn drop(&mut self) {}
}
