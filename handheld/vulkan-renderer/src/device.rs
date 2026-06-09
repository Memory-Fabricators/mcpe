// vulkan_renderer/src/device.rs — physical/logical device via ash.

use crate::instance::InstanceCtx;
use ash::khr;
use ash::vk;
use std::ffi::CStr;

pub struct DeviceCtx {
    pub physical: vk::PhysicalDevice,
    pub inner: ash::Device,
    pub graphics_queue: vk::Queue,
    pub present_queue: vk::Queue,
    pub graphics_family: u32,
    pub present_family: u32,
    pub properties: vk::PhysicalDeviceProperties,
    /// KHR swapchain extension functions for this device.
    pub swapchain_ext: khr::swapchain::Device,
}

pub fn select(instance: &InstanceCtx, window: *mut std::ffi::c_void) -> Result<DeviceCtx, String> {
    unsafe {
        let physical_devices = instance
            .inner
            .enumerate_physical_devices()
            .map_err(|e| format!("vkEnumeratePhysicalDevices failed: {e}"))?;

        if physical_devices.is_empty() {
            return Err("No Vulkan-capable physical devices found".into());
        }

        for physical in physical_devices {
            if let Ok(device) = try_create_device(instance, physical, window) {
                return Ok(device);
            }
        }

        Err("No suitable Vulkan device found".into())
    }
}

unsafe fn try_create_device(
    instance: &InstanceCtx,
    physical: vk::PhysicalDevice,
    window: *mut std::ffi::c_void,
) -> Result<DeviceCtx, String> {
    let queue_props = instance
        .inner
        .get_physical_device_queue_family_properties(physical);

    let properties = instance
        .inner
        .get_physical_device_properties(physical);

    // Find graphics queue family
    let graphics_family = queue_props
        .iter()
        .position(|p| p.queue_flags.contains(vk::QueueFlags::GRAPHICS))
        .map(|i| i as u32)
        .ok_or("No graphics queue family")?;

    // Create temporary surface to check present support
    let surface = create_surface(instance, window)?;

    let present_supported = instance
        .surface_ext
        .get_physical_device_surface_support(physical, graphics_family, surface)
        .map_err(|e| format!("get_physical_device_surface_support: {e}"))?;

    let present_family = if present_supported {
        graphics_family
    } else {
        let found = queue_props
            .iter()
            .enumerate()
            .find(|(i, _)| {
                instance
                    .surface_ext
                    .get_physical_device_surface_support(physical, *i as u32, surface)
                    .unwrap_or(false)
            })
            .map(|(i, _)| i as u32)
            .ok_or_else(|| {
                instance.surface_ext.destroy_surface(surface, None);
                "No present-capable queue family"
            })?;
        found
    };

    // Clean up temporary surface
    instance.surface_ext.destroy_surface(surface, None);

    // Create logical device
    let priorities = [1.0f32];
    let mut queue_infos = vec![vk::DeviceQueueCreateInfo::default()
        .queue_family_index(graphics_family)
        .queue_priorities(&priorities)];

    if present_family != graphics_family {
        queue_infos.push(
            vk::DeviceQueueCreateInfo::default()
                .queue_family_index(present_family)
                .queue_priorities(&priorities),
        );
    }

    let swapchain_name = CStr::from_bytes_with_nul(b"VK_KHR_swapchain\0").unwrap();
    let device_extensions = [swapchain_name.as_ptr()];

    let device_create_info = vk::DeviceCreateInfo::default()
        .queue_create_infos(&queue_infos)
        .enabled_extension_names(&device_extensions);

    let device = instance
        .inner
        .create_device(physical, &device_create_info, None)
        .map_err(|e| format!("vkCreateDevice failed: {e}"))?;

    let swapchain_ext = khr::swapchain::Device::load(&instance.inner, &device);

    let graphics_queue = device.get_device_queue(graphics_family, 0);
    let present_queue = device.get_device_queue(present_family, 0);

    Ok(DeviceCtx {
        physical,
        inner: device,
        graphics_queue,
        present_queue,
        graphics_family,
        present_family,
        properties,
        swapchain_ext,
    })
}

unsafe fn create_surface(
    instance: &InstanceCtx,
    _window: *mut std::ffi::c_void,
) -> Result<vk::SurfaceKHR, String> {
    unsafe extern "C" {
        fn sdl_vulkan_create_surface(window: *mut std::ffi::c_void, instance: vk::Instance) -> vk::SurfaceKHR;
    }
    let surface = sdl_vulkan_create_surface(_window, instance.inner.handle());
    if surface == vk::SurfaceKHR::null() {
        return Err("SDL_Vulkan_CreateSurface returned null".into());
    }
    Ok(surface)
}

impl Drop for DeviceCtx {
    fn drop(&mut self) {
        unsafe {
            self.inner.device_wait_idle().ok();
            self.inner.destroy_device(None);
        }
    }
}
