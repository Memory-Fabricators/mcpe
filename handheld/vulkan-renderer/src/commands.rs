// vulkan_renderer/src/commands.rs — command pool/buffers via ash.

use crate::device::DeviceCtx;
use ash::vk;

pub struct CommandContext {
    pub pool: vk::CommandPool,
    pub buffers: Vec<vk::CommandBuffer>,
    pub image_available: Vec<vk::Semaphore>,
    pub render_finished: Vec<vk::Semaphore>,
    pub in_flight_fences: Vec<vk::Fence>,
}

pub fn create(device: &DeviceCtx, image_count: u32) -> Result<CommandContext, String> {
    unsafe {
        let pool_create = vk::CommandPoolCreateInfo::default()
            .flags(vk::CommandPoolCreateFlags::RESET_COMMAND_BUFFER)
            .queue_family_index(device.graphics_family);

        let pool = device
            .inner
            .create_command_pool(&pool_create, None)
            .map_err(|e| format!("vkCreateCommandPool failed: {e}"))?;

        let alloc_info = vk::CommandBufferAllocateInfo::default()
            .command_pool(pool)
            .level(vk::CommandBufferLevel::PRIMARY)
            .command_buffer_count(image_count);

        let buffers = device
            .inner
            .allocate_command_buffers(&alloc_info)
            .map_err(|e| format!("vkAllocateCommandBuffers failed: {e}"))?;

        let sem_create = vk::SemaphoreCreateInfo::default();
        let fence_create = vk::FenceCreateInfo::default()
            .flags(vk::FenceCreateFlags::SIGNALED);

        let mut image_available = vec![];
        let mut render_finished = vec![];
        let mut in_flight_fences = vec![];

        for _ in 0..image_count {
            let sem = device
                .inner
                .create_semaphore(&sem_create, None)
                .map_err(|e| format!("vkCreateSemaphore failed: {e}"))?;
            image_available.push(sem);

            let sem2 = device
                .inner
                .create_semaphore(&sem_create, None)
                .map_err(|e| format!("vkCreateSemaphore failed: {e}"))?;
            render_finished.push(sem2);

            let fence = device
                .inner
                .create_fence(&fence_create, None)
                .map_err(|e| format!("vkCreateFence failed: {e}"))?;
            in_flight_fences.push(fence);
        }

        Ok(CommandContext { pool, buffers, image_available, render_finished, in_flight_fences })
    }
}

impl Drop for CommandContext {
    fn drop(&mut self) {}
}
