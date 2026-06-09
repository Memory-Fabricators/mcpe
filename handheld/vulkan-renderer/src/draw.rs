// vulkan_renderer/src/draw.rs — frame drawing via ash.

use crate::Renderer;
use ash::vk;

pub fn draw_frame(r: &Renderer) -> Result<(), String> {
    unsafe {
        let device = &r.device;
        let cmd = &r.cmd;

        let frame_idx = 0; // TODO: proper frame index management
        let cmd_buf = cmd.buffers[frame_idx];

        // Wait for previous frame
        device
            .inner
            .wait_for_fences(std::slice::from_ref(&cmd.in_flight_fences[frame_idx]), true, u64::MAX)
            .map_err(|e| format!("vkWaitForFences failed: {e}"))?;
        device
            .inner
            .reset_fences(std::slice::from_ref(&cmd.in_flight_fences[frame_idx]))
            .map_err(|e| format!("vkResetFences failed: {e}"))?;

        // Acquire next swapchain image
        let (image_index, _suboptimal) = device
            .swapchain_ext
            .acquire_next_image(
                r.swapchain.handle,
                u64::MAX,
                cmd.image_available[frame_idx],
                vk::Fence::null(),
            )
            .map_err(|e| format!("vkAcquireNextImageKHR failed: {e}"))?;

        // Reset and begin command buffer
        device
            .inner
            .reset_command_buffer(cmd_buf, vk::CommandBufferResetFlags::empty())
            .map_err(|e| format!("vkResetCommandBuffer failed: {e}"))?;

        let begin_info = vk::CommandBufferBeginInfo::default()
            .flags(vk::CommandBufferUsageFlags::ONE_TIME_SUBMIT);

        device
            .inner
            .begin_command_buffer(cmd_buf, &begin_info)
            .map_err(|e| format!("vkBeginCommandBuffer failed: {e}"))?;

        // Begin render pass
        let clear_color = vk::ClearValue {
            color: vk::ClearColorValue {
                float32: [0.0, 0.0, 0.0, 1.0],
            },
        };

        let render_pass_begin = vk::RenderPassBeginInfo::default()
            .render_pass(r.pipeline.render_pass)
            .framebuffer(r.swapchain.framebuffers[image_index as usize])
            .render_area(vk::Rect2D {
                offset: vk::Offset2D { x: 0, y: 0 },
                extent: r.swapchain.extent,
                ..Default::default()
            })
            .clear_values(std::slice::from_ref(&clear_color));

        device.inner.cmd_begin_render_pass(
            cmd_buf,
            &render_pass_begin,
            vk::SubpassContents::INLINE,
        );

        // Bind pipeline
        device.inner.cmd_bind_pipeline(
            cmd_buf,
            vk::PipelineBindPoint::GRAPHICS,
            r.pipeline.handle,
        );

        // Set viewport & scissor
        let viewport = vk::Viewport::default()
            .width(r.swapchain.extent.width as f32)
            .height(r.swapchain.extent.height as f32)
            .max_depth(1.0);
        device.inner.cmd_set_viewport(cmd_buf, 0, std::slice::from_ref(&viewport));

        let scissor = vk::Rect2D {
            offset: vk::Offset2D { x: 0, y: 0 },
            extent: r.swapchain.extent,
            ..Default::default()
        };
        device.inner.cmd_set_scissor(cmd_buf, 0, std::slice::from_ref(&scissor));

        // TODO: Bind vertex buffer and issue draw calls for each chunk/entity

        device.inner.cmd_end_render_pass(cmd_buf);
        device
            .inner
            .end_command_buffer(cmd_buf)
            .map_err(|e| format!("vkEndCommandBuffer failed: {e}"))?;

        // Submit
        let wait_stages = [vk::PipelineStageFlags::COLOR_ATTACHMENT_OUTPUT];
        let submit = vk::SubmitInfo::default()
            .wait_semaphores(std::slice::from_ref(&cmd.image_available[frame_idx]))
            .wait_dst_stage_mask(&wait_stages)
            .command_buffers(std::slice::from_ref(&cmd_buf))
            .signal_semaphores(std::slice::from_ref(&cmd.render_finished[frame_idx]));

        device
            .inner
            .queue_submit(device.graphics_queue, std::slice::from_ref(&submit), cmd.in_flight_fences[frame_idx])
            .map_err(|e| format!("vkQueueSubmit failed: {e}"))?;

        // Present
        let swapchains = [r.swapchain.handle];
        let image_indices = [image_index];
        let present = vk::PresentInfoKHR::default()
            .wait_semaphores(std::slice::from_ref(&cmd.render_finished[frame_idx]))
            .swapchains(&swapchains)
            .image_indices(&image_indices);

        device
            .swapchain_ext
            .queue_present(device.present_queue, &present)
            .map_err(|e| format!("vkQueuePresentKHR failed: {e}"))?;

        Ok(())
    }
}
