//! renderer.zig  –  public API of the Vulkan renderer module
//!
//! Import this file in your game main loop:
//!
//!   const renderer = @import("client/renderer/renderer.zig");
//!
//! Then initialise with:
//!   var ctx = try renderer.VkContext.init(alloc, window);
//!   var lr  = try renderer.LevelRenderer.init(alloc, &ctx, view_distance);
//!
//! Each frame:
//!   const img = try ctx.beginFrame();
//!   try lr.recordFrame(alloc, img, ...);
//!   try ctx.endFrame(img);

pub const vk = @import("vk_types.zig");
pub const loader = @import("vk_loader.zig");
pub const VkContext = @import("vk_context.zig").VkContext;
pub const Pipelines = @import("vk_pipeline.zig").Pipelines;
pub const GpuBuffer = @import("gpu_buffer.zig").GpuBuffer;
pub const Tesselator = @import("tesselator.zig").Tesselator;
pub const Vertex = @import("tesselator.zig").Vertex;
pub const LevelRenderer = @import("level_renderer.zig").LevelRenderer;
pub const RenderChunk = @import("level_renderer.zig").RenderChunk;
pub const ChunkSlot = @import("level_renderer.zig").ChunkSlot;
pub const CHUNK_SIZE = @import("level_renderer.zig").CHUNK_SIZE;
pub const RandomLevelSource = @import("world").RandomLevelSource;
