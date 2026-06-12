//! vk_pipeline.zig
//! Pipeline factory – creates the terrain, sky, and cloud pipelines.
//!
//! Each pipeline corresponds to one render pass in LevelRenderer:
//!   - terrain  : textured + depth-write, optional alpha-blend (layer 0/1)
//!   - sky      : no texture, no depth write, large quads above player
//!   - clouds   : textured, alpha-blend, no depth write

const std = @import("std");
const vk = @import("vk_types.zig");
const tess = @import("tesselator.zig");

// SPIR-V blobs embedded at compile time, guaranteed 4-byte aligned.
// @embedFile gives *const [N]u8 (align 1); VkShaderModuleCreateInfo.pCode
// needs align(4). We store each blob in an extern struct field so the
// compiler emits it with the required alignment.
fn SpvBlob(comptime bytes: []const u8) type {
    comptime std.debug.assert(bytes.len % 4 == 0);
    return extern struct { d: [bytes.len]u8 align(4) };
}
const TERRAIN_VERT_BLOB = SpvBlob(@embedFile("shaders/terrain.vert.spv")){ .d = @embedFile("shaders/terrain.vert.spv").* };
const TERRAIN_FRAG_BLOB = SpvBlob(@embedFile("shaders/terrain.frag.spv")){ .d = @embedFile("shaders/terrain.frag.spv").* };
const SKY_VERT_BLOB = SpvBlob(@embedFile("shaders/sky.vert.spv")){ .d = @embedFile("shaders/sky.vert.spv").* };
const SKY_FRAG_BLOB = SpvBlob(@embedFile("shaders/sky.frag.spv")){ .d = @embedFile("shaders/sky.frag.spv").* };
const CLOUD_VERT_BLOB = SpvBlob(@embedFile("shaders/clouds.vert.spv")){ .d = @embedFile("shaders/clouds.vert.spv").* };
const CLOUD_FRAG_BLOB = SpvBlob(@embedFile("shaders/clouds.frag.spv")){ .d = @embedFile("shaders/clouds.frag.spv").* };

const TERRAIN_VERT: []const u8 = &TERRAIN_VERT_BLOB.d;
const TERRAIN_FRAG: []const u8 = &TERRAIN_FRAG_BLOB.d;
const SKY_VERT: []const u8 = &SKY_VERT_BLOB.d;
const SKY_FRAG: []const u8 = &SKY_FRAG_BLOB.d;
const CLOUD_VERT: []const u8 = &CLOUD_VERT_BLOB.d;
const CLOUD_FRAG: []const u8 = &CLOUD_FRAG_BLOB.d;

/// One GPU pipeline + its layout + descriptor set layouts.
pub const Pipeline = struct {
    pipeline: vk.VkPipeline,
    layout: vk.VkPipelineLayout,
    /// set 0 layout (UBO + optional colour uniform)
    dset_layout_ubo: vk.VkDescriptorSetLayout,
    /// set 1 layout (combined image sampler) – 0 if unused
    dset_layout_tex: vk.VkDescriptorSetLayout,
};

pub const Pipelines = struct {
    terrain_opaque: Pipeline, // layer 0 – solid blocks
    terrain_alpha: Pipeline, // layer 1 – leaves / glass, alpha-test
    terrain_blend: Pipeline, // layer 2 – water, alpha-blend
    sky: Pipeline,
    clouds: Pipeline,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn createAll(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
) !Pipelines {
    return .{
        .terrain_opaque = try createTerrainPipeline(vf, device, render_pass, .opaque_solid),
        .terrain_alpha = try createTerrainPipeline(vf, device, render_pass, .alpha_test),
        .terrain_blend = try createTerrainPipeline(vf, device, render_pass, .alpha_blend),
        .sky = try createSkyPipeline(vf, device, render_pass),
        .clouds = try createCloudPipeline(vf, device, render_pass),
    };
}

pub fn destroyAll(vf: vk.VkFuncs, device: vk.VkDevice, p: *Pipelines) void {
    destroyPipeline(vf, device, &p.terrain_opaque);
    destroyPipeline(vf, device, &p.terrain_alpha);
    destroyPipeline(vf, device, &p.terrain_blend);
    destroyPipeline(vf, device, &p.sky);
    destroyPipeline(vf, device, &p.clouds);
}

fn destroyPipeline(vf: vk.VkFuncs, device: vk.VkDevice, p: *Pipeline) void {
    vf.vkDestroyPipeline(device, p.pipeline, null);
    vf.vkDestroyPipelineLayout(device, p.layout, null);
    vf.vkDestroyDescriptorSetLayout(device, p.dset_layout_ubo, null);
    if (p.dset_layout_tex != 0)
        vf.vkDestroyDescriptorSetLayout(device, p.dset_layout_tex, null);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makeShader(vf: vk.VkFuncs, device: vk.VkDevice, spv: []const u8) !vk.VkShaderModule {
    const ci = vk.VkShaderModuleCreateInfo{
        .sType = 16,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv.ptr)), // align(4) guaranteed by SpvBlob
    };
    var m: vk.VkShaderModule = 0;
    const r = vf.vkCreateShaderModule(device, &ci, null, &m);
    if (r != vk.VK_SUCCESS) return error.ShaderModuleCreateFailed;
    return m;
}

fn makeUboLayout(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    extra_bindings: []const vk.VkDescriptorSetLayoutBinding,
) !vk.VkDescriptorSetLayout {
    // binding 0: UBO, vertex+fragment
    var bindings_buf: [8]vk.VkDescriptorSetLayoutBinding = undefined;
    bindings_buf[0] = .{
        .binding = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_VERTEX_BIT | vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    for (extra_bindings, 0..) |b, i| bindings_buf[1 + i] = b;
    const total: u32 = @intCast(1 + extra_bindings.len);

    const ci = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = 32,
        .bindingCount = total,
        .pBindings = &bindings_buf,
    };
    var layout: vk.VkDescriptorSetLayout = 0;
    const r = vf.vkCreateDescriptorSetLayout(device, &ci, null, &layout);
    if (r != vk.VK_SUCCESS) return error.DSLCreateFailed;
    return layout;
}

fn makeTexLayout(vf: vk.VkFuncs, device: vk.VkDevice) !vk.VkDescriptorSetLayout {
    const b = vk.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    const ci = vk.VkDescriptorSetLayoutCreateInfo{
        .sType = 32,
        .bindingCount = 1,
        .pBindings = @as([*]const vk.VkDescriptorSetLayoutBinding, @ptrCast(&b)),
    };
    var layout: vk.VkDescriptorSetLayout = 0;
    const r = vf.vkCreateDescriptorSetLayout(device, &ci, null, &layout);
    if (r != vk.VK_SUCCESS) return error.DSLCreateFailed;
    return layout;
}

fn makeLayout(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    set_layouts: []const vk.VkDescriptorSetLayout,
) !vk.VkPipelineLayout {
    const ci = vk.VkPipelineLayoutCreateInfo{
        .sType = 30,
        .setLayoutCount = @intCast(set_layouts.len),
        .pSetLayouts = set_layouts.ptr,
    };
    var layout: vk.VkPipelineLayout = 0;
    const r = vf.vkCreatePipelineLayout(device, &ci, null, &layout);
    if (r != vk.VK_SUCCESS) return error.PipelineLayoutCreateFailed;
    return layout;
}

// Terrain vertex bindings (Vertex = 24 bytes)
const terrain_binding = vk.VkVertexInputBindingDescription{
    .binding = 0,
    .stride = @sizeOf(tess.Vertex),
    .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
};
const terrain_attribs = [_]vk.VkVertexInputAttributeDescription{
    .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 }, // pos
    .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 12 }, // uv
    .{ .location = 2, .binding = 0, .format = vk.VK_FORMAT_R8G8B8A8_UNORM, .offset = 20 }, // color (u8×4 → float vec4)
};

const BlendMode = enum { opaque_solid, alpha_test, alpha_blend };

fn createTerrainPipeline(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
    blend: BlendMode,
) !Pipeline {
    const vert = try makeShader(vf, device, TERRAIN_VERT);
    const frag = try makeShader(vf, device, TERRAIN_FRAG);
    defer vf.vkDestroyShaderModule(device, vert, null);
    defer vf.vkDestroyShaderModule(device, frag, null);

    const ubo_layout = try makeUboLayout(vf, device, &.{});
    const tex_layout = try makeTexLayout(vf, device);
    const set_layouts = [_]vk.VkDescriptorSetLayout{ ubo_layout, tex_layout };
    const pipe_layout = try makeLayout(vf, device, &set_layouts);

    const stages = [_]vk.VkPipelineShaderStageCreateInfo{
        .{ .sType = 18, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert, .pName = "main" },
        .{ .sType = 18, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag, .pName = "main" },
    };
    const vi = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = 19,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &[1]vk.VkVertexInputBindingDescription{terrain_binding},
        .vertexAttributeDescriptionCount = terrain_attribs.len,
        .pVertexAttributeDescriptions = &terrain_attribs,
    };
    const ia = vk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = 20,
        .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    const vp_state = vk.VkPipelineViewportStateCreateInfo{ .sType = 22, .viewportCount = 1, .scissorCount = 1 };
    const raster = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = 23,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_BACK_BIT,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0,
    };
    const ms = vk.VkPipelineMultisampleStateCreateInfo{
        .sType = 24,
        .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT,
    };
    const depth_stencil = vk.VkPipelineDepthStencilStateCreateInfo{
        .sType = 25,
        .depthTestEnable = 1,
        .depthWriteEnable = if (blend == .alpha_blend) 0 else 1,
        .depthCompareOp = vk.VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    const blend_att = switch (blend) {
        .opaque_solid, .alpha_test => vk.VkPipelineColorBlendAttachmentState{
            .blendEnable = 0,
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .colorBlendOp = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = vk.VK_BLEND_OP_ADD,
            .colorWriteMask = vk.VK_COLOR_COMPONENT_ALL,
        },
        .alpha_blend => vk.VkPipelineColorBlendAttachmentState{
            .blendEnable = 1,
            .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
            .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
            .colorBlendOp = vk.VK_BLEND_OP_ADD,
            .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
            .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
            .alphaBlendOp = vk.VK_BLEND_OP_ADD,
            .colorWriteMask = vk.VK_COLOR_COMPONENT_ALL,
        },
    };
    const cb = vk.VkPipelineColorBlendStateCreateInfo{
        .sType = 26,
        .attachmentCount = 1,
        .pAttachments = &[1]vk.VkPipelineColorBlendAttachmentState{blend_att},
    };
    const dyn_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const dyn = vk.VkPipelineDynamicStateCreateInfo{
        .sType = 27,
        .dynamicStateCount = dyn_states.len,
        .pDynamicStates = &dyn_states,
    };

    const gfx_ci = vk.VkGraphicsPipelineCreateInfo{
        .sType = 28,
        .flags = vk.VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT,
        .stageCount = stages.len,
        .pStages = &stages,
        .pVertexInputState = &vi,
        .pInputAssemblyState = &ia,
        .pViewportState = &vp_state,
        .pRasterizationState = &raster,
        .pMultisampleState = &ms,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &cb,
        .pDynamicState = &dyn,
        .layout = pipe_layout,
        .renderPass = render_pass,
        .subpass = 0,
    };
    var pipes = [_]vk.VkPipeline{0};
    const r2 = vf.vkCreateGraphicsPipelines(device, 0, 1, &[_]vk.VkGraphicsPipelineCreateInfo{gfx_ci}, null, &pipes);
    if (r2 != vk.VK_SUCCESS) return error.PipelineCreateFailed;
    const pipe = pipes[0];

    return .{
        .pipeline = pipe,
        .layout = pipe_layout,
        .dset_layout_ubo = ubo_layout,
        .dset_layout_tex = tex_layout,
    };
}

fn createSkyPipeline(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
) !Pipeline {
    const vert = try makeShader(vf, device, SKY_VERT);
    const frag = try makeShader(vf, device, SKY_FRAG);
    defer vf.vkDestroyShaderModule(device, vert, null);
    defer vf.vkDestroyShaderModule(device, frag, null);

    // set 0: binding 0 = UBO (mvp+offset), binding 1 = sky colour uniform
    const extra_bind = vk.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    const ubo_layout = try makeUboLayout(vf, device, &[_]vk.VkDescriptorSetLayoutBinding{extra_bind});
    const set_layouts = [_]vk.VkDescriptorSetLayout{ubo_layout};
    const pipe_layout = try makeLayout(vf, device, &set_layouts);

    // Sky: position only (xyz)
    const sky_binding = vk.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = 12,
        .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const sky_attrib = vk.VkVertexInputAttributeDescription{
        .location = 0,
        .binding = 0,
        .format = vk.VK_FORMAT_R32G32B32_SFLOAT,
        .offset = 0,
    };

    const stages = [_]vk.VkPipelineShaderStageCreateInfo{
        .{ .sType = 18, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert, .pName = "main" },
        .{ .sType = 18, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag, .pName = "main" },
    };
    const vi = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = 19,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &[1]vk.VkVertexInputBindingDescription{sky_binding},
        .vertexAttributeDescriptionCount = 1,
        .pVertexAttributeDescriptions = &[1]vk.VkVertexInputAttributeDescription{sky_attrib},
    };
    const ia = vk.VkPipelineInputAssemblyStateCreateInfo{ .sType = 20, .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
    const vp_state = vk.VkPipelineViewportStateCreateInfo{ .sType = 22, .viewportCount = 1, .scissorCount = 1 };
    const raster = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = 23,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_NONE,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0,
    };
    const ms = vk.VkPipelineMultisampleStateCreateInfo{ .sType = 24, .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT };
    const depth_stencil = vk.VkPipelineDepthStencilStateCreateInfo{
        .sType = 25,
        .depthTestEnable = 0,
        .depthWriteEnable = 0,
        .depthCompareOp = vk.VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    const blend_att = vk.VkPipelineColorBlendAttachmentState{
        .blendEnable = 0,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_ALL,
    };
    const cb = vk.VkPipelineColorBlendStateCreateInfo{ .sType = 26, .attachmentCount = 1, .pAttachments = &[1]vk.VkPipelineColorBlendAttachmentState{blend_att} };
    const dyn_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const dyn = vk.VkPipelineDynamicStateCreateInfo{ .sType = 27, .dynamicStateCount = 2, .pDynamicStates = &dyn_states };

    const gfx_ci = vk.VkGraphicsPipelineCreateInfo{
        .sType = 28,
        .flags = vk.VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT,
        .stageCount = 2,
        .pStages = &stages,
        .pVertexInputState = &vi,
        .pInputAssemblyState = &ia,
        .pViewportState = &vp_state,
        .pRasterizationState = &raster,
        .pMultisampleState = &ms,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &cb,
        .pDynamicState = &dyn,
        .layout = pipe_layout,
        .renderPass = render_pass,
        .subpass = 0,
    };
    var pipes = [_]vk.VkPipeline{0};
    const r = vf.vkCreateGraphicsPipelines(device, 0, 1, &[_]vk.VkGraphicsPipelineCreateInfo{gfx_ci}, null, &pipes);
    if (r != vk.VK_SUCCESS) return error.PipelineCreateFailed;

    return .{
        .pipeline = pipes[0],
        .layout = pipe_layout,
        .dset_layout_ubo = ubo_layout,
        .dset_layout_tex = 0,
    };
}

fn createCloudPipeline(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    render_pass: vk.VkRenderPass,
) !Pipeline {
    const vert = try makeShader(vf, device, CLOUD_VERT);
    const frag = try makeShader(vf, device, CLOUD_FRAG);
    defer vf.vkDestroyShaderModule(device, vert, null);
    defer vf.vkDestroyShaderModule(device, frag, null);

    // set 0: binding 0 = UBO, binding 1 = cloud colour
    const extra_bind = vk.VkDescriptorSetLayoutBinding{
        .binding = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = vk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    const ubo_layout = try makeUboLayout(vf, device, &[_]vk.VkDescriptorSetLayoutBinding{extra_bind});
    const set_layouts = [_]vk.VkDescriptorSetLayout{ubo_layout};
    const pipe_layout = try makeLayout(vf, device, &set_layouts);

    // Cloud vertex: pos(xyz) + uv
    const cloud_binding = vk.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = 20,
        .inputRate = vk.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const cloud_attribs = [_]vk.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = vk.VK_FORMAT_R32G32B32_SFLOAT, .offset = 0 },
        .{ .location = 1, .binding = 0, .format = vk.VK_FORMAT_R32G32_SFLOAT, .offset = 12 },
    };

    const stages = [_]vk.VkPipelineShaderStageCreateInfo{
        .{ .sType = 18, .stage = vk.VK_SHADER_STAGE_VERTEX_BIT, .module = vert, .pName = "main" },
        .{ .sType = 18, .stage = vk.VK_SHADER_STAGE_FRAGMENT_BIT, .module = frag, .pName = "main" },
    };
    const vi = vk.VkPipelineVertexInputStateCreateInfo{
        .sType = 19,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &[1]vk.VkVertexInputBindingDescription{cloud_binding},
        .vertexAttributeDescriptionCount = cloud_attribs.len,
        .pVertexAttributeDescriptions = &cloud_attribs,
    };
    const ia = vk.VkPipelineInputAssemblyStateCreateInfo{ .sType = 20, .topology = vk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST };
    const vp_state = vk.VkPipelineViewportStateCreateInfo{ .sType = 22, .viewportCount = 1, .scissorCount = 1 };
    const raster = vk.VkPipelineRasterizationStateCreateInfo{
        .sType = 23,
        .polygonMode = vk.VK_POLYGON_MODE_FILL,
        .cullMode = vk.VK_CULL_MODE_BACK_BIT,
        .frontFace = vk.VK_FRONT_FACE_COUNTER_CLOCKWISE,
        .lineWidth = 1.0,
    };
    const ms = vk.VkPipelineMultisampleStateCreateInfo{ .sType = 24, .rasterizationSamples = vk.VK_SAMPLE_COUNT_1_BIT };
    const depth_stencil = vk.VkPipelineDepthStencilStateCreateInfo{
        .sType = 25,
        .depthTestEnable = 1,
        .depthWriteEnable = 0,
        .depthCompareOp = vk.VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    const blend_att = vk.VkPipelineColorBlendAttachmentState{
        .blendEnable = 1,
        .srcColorBlendFactor = vk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = vk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = vk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = vk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = vk.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = vk.VK_BLEND_OP_ADD,
        .colorWriteMask = vk.VK_COLOR_COMPONENT_ALL,
    };
    const cb = vk.VkPipelineColorBlendStateCreateInfo{ .sType = 26, .attachmentCount = 1, .pAttachments = &[1]vk.VkPipelineColorBlendAttachmentState{blend_att} };
    const dyn_states = [_]vk.VkDynamicState{ vk.VK_DYNAMIC_STATE_VIEWPORT, vk.VK_DYNAMIC_STATE_SCISSOR };
    const dyn = vk.VkPipelineDynamicStateCreateInfo{ .sType = 27, .dynamicStateCount = 2, .pDynamicStates = &dyn_states };

    const gfx_ci = vk.VkGraphicsPipelineCreateInfo{
        .sType = 28,
        .flags = vk.VK_PIPELINE_CREATE_DISABLE_OPTIMIZATION_BIT,
        .stageCount = 2,
        .pStages = &stages,
        .pVertexInputState = &vi,
        .pInputAssemblyState = &ia,
        .pViewportState = &vp_state,
        .pRasterizationState = &raster,
        .pMultisampleState = &ms,
        .pDepthStencilState = &depth_stencil,
        .pColorBlendState = &cb,
        .pDynamicState = &dyn,
        .layout = pipe_layout,
        .renderPass = render_pass,
        .subpass = 0,
    };
    var pipes = [_]vk.VkPipeline{0};
    const r = vf.vkCreateGraphicsPipelines(device, 0, 1, &[_]vk.VkGraphicsPipelineCreateInfo{gfx_ci}, null, &pipes);
    if (r != vk.VK_SUCCESS) return error.PipelineCreateFailed;

    return .{
        .pipeline = pipes[0],
        .layout = pipe_layout,
        .dset_layout_ubo = ubo_layout,
        .dset_layout_tex = 0,
    };
}
