// vulkan_renderer/src/buffers.rs — vertex buffer via ash.

use crate::instance::InstanceCtx;
use crate::device::DeviceCtx;
use ash::vk;

pub struct BufferManager {
    pub vertex_buffer: vk::Buffer,
    pub vertex_memory: vk::DeviceMemory,
    pub vertex_mapped: *mut std::ffi::c_void,
    pub buffer_size: u64,
}

pub fn create(instance: &InstanceCtx, device: &DeviceCtx) -> Result<BufferManager, String> {
    unsafe {
        let buffer_size: u64 = 16 * 1024 * 1024;

        let buffer_create = vk::BufferCreateInfo::default()
            .size(buffer_size)
            .usage(vk::BufferUsageFlags::VERTEX_BUFFER)
            .sharing_mode(vk::SharingMode::EXCLUSIVE);

        let vertex_buffer = device
            .inner
            .create_buffer(&buffer_create, None)
            .map_err(|e| format!("vkCreateBuffer failed: {e}"))?;

        let mem_req = device.inner.get_buffer_memory_requirements(vertex_buffer);

        let memory_type = find_memory_type(
            instance,
            device.physical,
            mem_req.memory_type_bits,
            vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT,
        )?;

        let alloc_info = vk::MemoryAllocateInfo::default()
            .allocation_size(mem_req.size)
            .memory_type_index(memory_type);

        let vertex_memory = device
            .inner
            .allocate_memory(&alloc_info, None)
            .map_err(|e| {
                device.inner.destroy_buffer(vertex_buffer, None);
                format!("vkAllocateMemory failed: {e}")
            })?;

        device
            .inner
            .bind_buffer_memory(vertex_buffer, vertex_memory, 0)
            .map_err(|e| {
                device.inner.free_memory(vertex_memory, None);
                device.inner.destroy_buffer(vertex_buffer, None);
                format!("vkBindBufferMemory failed: {e}")
            })?;

        let mapped = device
            .inner
            .map_memory(vertex_memory, 0, buffer_size, vk::MemoryMapFlags::empty())
            .map_err(|e| {
                device.inner.free_memory(vertex_memory, None);
                device.inner.destroy_buffer(vertex_buffer, None);
                format!("vkMapMemory failed: {e}")
            })?;

        Ok(BufferManager {
            vertex_buffer,
            vertex_memory,
            vertex_mapped: mapped,
            buffer_size,
        })
    }
}

unsafe fn find_memory_type(
    instance: &InstanceCtx,
    physical_device: vk::PhysicalDevice,
    type_filter: u32,
    required_props: vk::MemoryPropertyFlags,
) -> Result<u32, String> {
    let mem_props = instance.inner.get_physical_device_memory_properties(physical_device);

    for i in 0..mem_props.memory_type_count {
        let flags = mem_props.memory_types[i as usize].property_flags;
        if (type_filter & (1 << i)) != 0 && flags.contains(required_props) {
            return Ok(i);
        }
    }
    Err(format!(
        "No suitable memory type for filter=0x{type_filter:X}"
    ))
}

impl Drop for BufferManager {
    fn drop(&mut self) {}
}
