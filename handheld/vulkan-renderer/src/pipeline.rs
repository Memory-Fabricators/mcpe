// vulkan_renderer/src/pipeline.rs — graphics pipeline via ash.

use crate::device::DeviceCtx;
use crate::swapchain::Swapchain;
use crate::shaders;
use ash::vk;

pub struct Pipeline {
    pub layout: vk::PipelineLayout,
    pub handle: vk::Pipeline,
    pub render_pass: vk::RenderPass,
}

pub fn create(device: &DeviceCtx, swapchain: &Swapchain) -> Result<Pipeline, String> {
    unsafe {
        let render_pass = create_render_pass(device, swapchain.format)?;
        let vert_module = create_shader_module(device, shaders::VERT_SPV)?;
        let frag_module = create_shader_module(device, shaders::FRAG_SPV)?;

        let entry = std::ffi::CStr::from_bytes_with_nul(b"main\0").unwrap();

        let vert_stage = vk::PipelineShaderStageCreateInfo::default()
            .stage(vk::ShaderStageFlags::VERTEX)
            .module(vert_module)
            .name(entry);

        let frag_stage = vk::PipelineShaderStageCreateInfo::default()
            .stage(vk::ShaderStageFlags::FRAGMENT)
            .module(frag_module)
            .name(entry);

        let stages = [vert_stage, frag_stage];

        // Vertex input — matches VertexDeclPTC { xyz:3f, uv:2f, color:4u8 }
        let vertex_bindings = [vk::VertexInputBindingDescription::default()
            .binding(0)
            .stride(24)
            .input_rate(vk::VertexInputRate::VERTEX)];

        let vertex_attrs = [
            vk::VertexInputAttributeDescription::default()
                .location(0).binding(0).format(vk::Format::R32G32B32_SFLOAT).offset(0),
            vk::VertexInputAttributeDescription::default()
                .location(1).binding(0).format(vk::Format::R32G32_SFLOAT).offset(12),
            vk::VertexInputAttributeDescription::default()
                .location(2).binding(0).format(vk::Format::B8G8R8A8_UNORM).offset(20),
        ];

        let vertex_input = vk::PipelineVertexInputStateCreateInfo::default()
            .vertex_binding_descriptions(&vertex_bindings)
            .vertex_attribute_descriptions(&vertex_attrs);

        let input_assembly = vk::PipelineInputAssemblyStateCreateInfo::default()
            .topology(vk::PrimitiveTopology::TRIANGLE_LIST);

        let viewport_state = vk::PipelineViewportStateCreateInfo::default()
            .viewport_count(1)
            .scissor_count(1);

        let rasterizer = vk::PipelineRasterizationStateCreateInfo::default()
            .polygon_mode(vk::PolygonMode::FILL)
            .cull_mode(vk::CullModeFlags::NONE)
            .front_face(vk::FrontFace::COUNTER_CLOCKWISE)
            .line_width(1.0);

        let multisampling = vk::PipelineMultisampleStateCreateInfo::default()
            .rasterization_samples(vk::SampleCountFlags::TYPE_1);

        let depth_stencil = vk::PipelineDepthStencilStateCreateInfo::default()
            .depth_compare_op(vk::CompareOp::LESS);

        let color_blend_attachment = vk::PipelineColorBlendAttachmentState::default()
            .blend_enable(true)
            .src_color_blend_factor(vk::BlendFactor::SRC_ALPHA)
            .dst_color_blend_factor(vk::BlendFactor::ONE_MINUS_SRC_ALPHA)
            .color_blend_op(vk::BlendOp::ADD)
            .src_alpha_blend_factor(vk::BlendFactor::ONE)
            .dst_alpha_blend_factor(vk::BlendFactor::ZERO)
            .alpha_blend_op(vk::BlendOp::ADD)
            .color_write_mask(
                vk::ColorComponentFlags::R
                    | vk::ColorComponentFlags::G
                    | vk::ColorComponentFlags::B
                    | vk::ColorComponentFlags::A,
            );

        let color_blend = vk::PipelineColorBlendStateCreateInfo::default()
            .attachments(std::slice::from_ref(&color_blend_attachment));

        let dynamic_states = [vk::DynamicState::VIEWPORT, vk::DynamicState::SCISSOR];
        let dynamic_state = vk::PipelineDynamicStateCreateInfo::default()
            .dynamic_states(&dynamic_states);

        let push_constant_range = vk::PushConstantRange::default()
            .stage_flags(vk::ShaderStageFlags::VERTEX | vk::ShaderStageFlags::FRAGMENT)
            .offset(0)
            .size(128);

        let layout_create_info = vk::PipelineLayoutCreateInfo::default()
            .push_constant_ranges(std::slice::from_ref(&push_constant_range));

        let layout = device
            .inner
            .create_pipeline_layout(&layout_create_info, None)
            .map_err(|e| format!("vkCreatePipelineLayout failed: {e}"))?;

        let pipeline_create_info = vk::GraphicsPipelineCreateInfo::default()
            .stages(&stages)
            .vertex_input_state(&vertex_input)
            .input_assembly_state(&input_assembly)
            .viewport_state(&viewport_state)
            .rasterization_state(&rasterizer)
            .multisample_state(&multisampling)
            .depth_stencil_state(&depth_stencil)
            .color_blend_state(&color_blend)
            .dynamic_state(&dynamic_state)
            .layout(layout)
            .render_pass(render_pass)
            .subpass(0);

        let pipeline = device
            .inner
            .create_graphics_pipelines(
                vk::PipelineCache::null(),
                std::slice::from_ref(&pipeline_create_info),
                None,
            )
            .map_err(|(_, e)| format!("vkCreateGraphicsPipelines failed: {e}"))?[0];

        // Cleanup shader modules
        device.inner.destroy_shader_module(vert_module, None);
        device.inner.destroy_shader_module(frag_module, None);

        Ok(Pipeline { layout, handle: pipeline, render_pass })
    }
}

unsafe fn create_render_pass(device: &DeviceCtx, format: vk::Format) -> Result<vk::RenderPass, String> {
    let color_attachment = vk::AttachmentDescription::default()
        .format(format)
        .samples(vk::SampleCountFlags::TYPE_1)
        .load_op(vk::AttachmentLoadOp::CLEAR)
        .store_op(vk::AttachmentStoreOp::STORE)
        .initial_layout(vk::ImageLayout::UNDEFINED)
        .final_layout(vk::ImageLayout::PRESENT_SRC_KHR);

    let color_ref = vk::AttachmentReference::default()
        .attachment(0)
        .layout(vk::ImageLayout::COLOR_ATTACHMENT_OPTIMAL);

    let subpass = vk::SubpassDescription::default()
        .pipeline_bind_point(vk::PipelineBindPoint::GRAPHICS)
        .color_attachments(std::slice::from_ref(&color_ref));

    let render_pass_create = vk::RenderPassCreateInfo::default()
        .attachments(std::slice::from_ref(&color_attachment))
        .subpasses(std::slice::from_ref(&subpass));

    let render_pass = device
        .inner
        .create_render_pass(&render_pass_create, None)
        .map_err(|e| format!("vkCreateRenderPass failed: {e}"))?;

    Ok(render_pass)
}

unsafe fn create_shader_module(device: &DeviceCtx, code: &[u8]) -> Result<vk::ShaderModule, String> {
    if code.is_empty() {
        return Err("Shader bytecode is empty — SPIR-V not yet compiled".into());
    }

    let create_info = vk::ShaderModuleCreateInfo::default()
        .code(unsafe { std::slice::from_raw_parts(code.as_ptr() as *const u32, code.len() / 4) });

    let module = device
        .inner
        .create_shader_module(&create_info, None)
        .map_err(|e| format!("vkCreateShaderModule failed: {e}"))?;

    Ok(module)
}

impl Drop for Pipeline {
    fn drop(&mut self) {}
}
