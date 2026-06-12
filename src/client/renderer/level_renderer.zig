//! level_renderer.zig
//! Vulkan port of LevelRenderer.cpp / LevelRenderer.h
//!
//! Responsibilities (matching the C++ original):
//!   • Maintain a 3-D grid of RenderChunks (dirty-tracking, resort by dist)
//!   • renderSky   – flat sky dome drawn as a grid of quads above the player
//!   • renderClouds – scrolling cloud plane textured with clouds.png
//!   • render      – iterate visible chunks, issue draw calls per layer
//!
//! What we *don't* port yet (marked TODO):
//!   • Entity / tile-entity dispatch
//!   • Particle engine draw
//!   • Hit-select / hit-outline overlays
//!   • Occlusion queries (the C++ code had them disabled at runtime anyway)

const std = @import("std");
const math = std.math;
const zm = @import("math");
const Mat4 = zm.Mat;
const Vec = zm.Vec;
const vk = @import("vk_types.zig");
const ctx = @import("vk_context.zig");
const pip = @import("vk_pipeline.zig");
const gpu = @import("gpu_buffer.zig");
const tss = @import("tesselator.zig");
const rls = @import("world");
const chunk = rls.chunk;
const png = @import("png");

// ---------------------------------------------------------------------------
// Constants (mirroring C++ LevelRenderer)
// ---------------------------------------------------------------------------

/// Number of world blocks per render chunk side (was 8 or 16 depending on
/// GFX_SMALLER_CHUNKS; we always use 16 here).
pub const CHUNK_SIZE: i32 = 16;

/// Number of geometry layers per chunk.
///   0 = opaque solid
///   1 = alpha-tested (leaves, glass)
///   2 = alpha-blended (water)
pub const NUM_LAYERS: usize = 3;

/// Maximum dirty chunks rebuilt per frame for chunks within 32 m.
pub const MAX_VISIBLE_REBUILDS_PER_FRAME: usize = 3;
/// Maximum dirty chunks rebuilt per frame for off-screen chunks.
pub const MAX_INVISIBLE_REBUILDS_PER_FRAME: usize = 1;

/// Shared chunk vertex buffer arena size (64 MiB).
const CHUNK_ARENA_BYTES: vk.VkDeviceSize = 64 * 1024 * 1024;

/// Sky grid parameters (mirror C++ generateSky)
const SKY_QUAD_SIZE: f32 = 128.0;
const SKY_Y_OFFSET: f32 = 16.0; // y of the sky plane above camera

/// Cloud grid parameters (mirror C++ renderClouds)
const CLOUD_SEG: f32 = 32.0;
const CLOUD_DIVS: i32 = 8; // 256 / 32 = 8

pub const VulkanBufferPool = struct {
    pub const Allocation = struct {
        buffer: vk.VkBuffer,
        memory: vk.VkDeviceMemory,
        offset: vk.VkDeviceSize,
        size: vk.VkDeviceSize,
        arena_idx: usize,
    };

    const Block = struct {
        offset: vk.VkDeviceSize,
        size: vk.VkDeviceSize,
        free: bool,
    };

    const Arena = struct {
        buffer: vk.VkBuffer,
        memory: vk.VkDeviceMemory,
        blocks: std.ArrayList(Block),
        size: vk.VkDeviceSize,
    };

    context: *ctx.VkContext,
    arenas: std.ArrayList(Arena),
    arena_size: vk.VkDeviceSize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, context: *ctx.VkContext, arena_size: vk.VkDeviceSize) VulkanBufferPool {
        return .{
            .context = context,
            .arenas = .empty,
            .arena_size = arena_size,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *VulkanBufferPool) void {
        for (self.arenas.items) |*arena| {
            self.context.vf.vkDestroyBuffer(self.context.device, arena.buffer, null);
            self.context.vf.vkFreeMemory(self.context.device, arena.memory, null);
            arena.blocks.deinit(self.allocator);
        }
        self.arenas.deinit(self.allocator);
    }

    fn createArena(self: *VulkanBufferPool, size: vk.VkDeviceSize) !Arena {
        var buffer: vk.VkBuffer = 0;
        var memory: vk.VkDeviceMemory = 0;
        try self.context.createBuffer(
            size,
            vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &buffer,
            &memory,
        );

        var blocks = std.ArrayList(Block).empty;
        try blocks.append(self.allocator, .{
            .offset = 0,
            .size = size,
            .free = true,
        });

        return Arena{
            .buffer = buffer,
            .memory = memory,
            .blocks = blocks,
            .size = size,
        };
    }

    pub fn allocate(self: *VulkanBufferPool, size: vk.VkDeviceSize, alignment: vk.VkDeviceSize) !Allocation {
        if (size == 0) return error.InvalidAllocationSize;
        const effective_alignment: vk.VkDeviceSize = if (alignment == 0) 1 else alignment;
        const aligned_size = (size + effective_alignment - 1) & ~(effective_alignment - 1);

        for (self.arenas.items, 0..) |*arena, arena_idx| {
            for (0..arena.blocks.items.len) |block_idx| {
                const block = arena.blocks.items[block_idx];
                if (!block.free or block.size < aligned_size) continue;

                const original_size = block.size;
                arena.blocks.items[block_idx].free = false;

                if (original_size - aligned_size >= 256) {
                    arena.blocks.items[block_idx].size = aligned_size;
                    const new_block = Block{
                        .offset = block.offset + aligned_size,
                        .size = original_size - aligned_size,
                        .free = true,
                    };
                    try arena.blocks.insert(self.allocator, block_idx + 1, new_block);
                }

                return Allocation{
                    .buffer = arena.buffer,
                    .memory = arena.memory,
                    .offset = arena.blocks.items[block_idx].offset,
                    .size = arena.blocks.items[block_idx].size,
                    .arena_idx = arena_idx,
                };
            }
        }

        const needed_size = @max(self.arena_size, aligned_size);
        const new_arena = try self.createArena(needed_size);
        try self.arenas.append(self.allocator, new_arena);

        const arena_idx = self.arenas.items.len - 1;
        const arena = &self.arenas.items[arena_idx];
        arena.blocks.items[0].free = false;

        const original_size = arena.blocks.items[0].size;
        if (original_size - aligned_size >= 256) {
            arena.blocks.items[0].size = aligned_size;
            const new_block = Block{
                .offset = aligned_size,
                .size = original_size - aligned_size,
                .free = true,
            };
            try arena.blocks.insert(self.allocator, 1, new_block);
        }

        return Allocation{
            .buffer = arena.buffer,
            .memory = arena.memory,
            .offset = arena.blocks.items[0].offset,
            .size = arena.blocks.items[0].size,
            .arena_idx = arena_idx,
        };
    }

    pub fn free(self: *VulkanBufferPool, alloc: Allocation) void {
        if (alloc.arena_idx >= self.arenas.items.len) return;
        const arena = &self.arenas.items[alloc.arena_idx];

        for (arena.blocks.items) |*block| {
            if (block.offset == alloc.offset) {
                block.free = true;
                break;
            }
        }

        if (arena.blocks.items.len < 2) return;
        var i: usize = 0;
        while (i + 1 < arena.blocks.items.len) {
            if (arena.blocks.items[i].free and arena.blocks.items[i + 1].free) {
                arena.blocks.items[i].size += arena.blocks.items[i + 1].size;
                _ = arena.blocks.orderedRemove(i + 1);
            } else {
                i += 1;
            }
        }
    }
};

// ---------------------------------------------------------------------------
// UBO layout (must match terrain.vert / sky.vert / clouds.vert)
// ---------------------------------------------------------------------------

const UboData = extern struct {
    mvp: [16]f32,
    offset: [3]f32,
    _pad: f32 = 0,
};

const SkyColorData = extern struct {
    color: [4]f32,
};

const CloudColorData = extern struct {
    color: [4]f32,
};

// ---------------------------------------------------------------------------
// RenderChunk – one layer of one 16³ world chunk
// ---------------------------------------------------------------------------

pub const RenderChunk = struct {
    vbuf_alloc: ?VulkanBufferPool.Allocation = null,
    vertex_count: u32 = 0,
    dirty: bool = true,
    empty: bool = true,

    /// Rebuild this chunk layer by calling into TileRenderer (stub for now).
    pub fn rebuild(_: *RenderChunk) void {
        // TODO: call TileRenderer to fill vbuf
    }
};

// ---------------------------------------------------------------------------
// ChunkSlot – 3 render layers for one world position
// ---------------------------------------------------------------------------

pub const ChunkSlot = struct {
    /// World block position of the chunk's lower-left-back corner.
    x: i32 = 0,
    y: i32 = 0,
    z: i32 = 0,

    layers: [NUM_LAYERS]RenderChunk = undefined,

    visible: bool = true,
    sky_lit: bool = false,
    dirty: bool = true,
    id: u32 = 0,
    rebuilding: bool = false,

    /// Distance² to player for sorting.
    pub fn distSqr(self: *const ChunkSlot, px: f32, py: f32, pz: f32) f32 {
        const dx = @as(f32, @floatFromInt(self.x)) + @as(f32, @floatFromInt(CHUNK_SIZE)) / 2.0 - px;
        const dy = @as(f32, @floatFromInt(self.y)) + @as(f32, @floatFromInt(CHUNK_SIZE)) / 2.0 - py;
        const dz = @as(f32, @floatFromInt(self.z)) + @as(f32, @floatFromInt(CHUNK_SIZE)) / 2.0 - pz;
        return dx * dx + dy * dy + dz * dz;
    }

    pub fn setDirty(self: *ChunkSlot) void {
        self.dirty = true;
        for (&self.layers) |*l| l.dirty = true;
    }

    pub fn setClean(self: *ChunkSlot) void {
        self.dirty = false;
    }

    pub fn isEmpty(self: *const ChunkSlot) bool {
        for (&self.layers) |l| if (!l.empty) return false;
        return true;
    }
};

const RebuildResult = struct {
    slot_idx: usize,
    expected_x: i32,
    expected_y: i32,
    expected_z: i32,
    layers: [NUM_LAYERS]struct {
        verts: []const tss.Vertex,
    },
};

const LocalChunkData = struct {
    blocks: [18 * 18 * 18]u8,

    pub fn getBlock(self: *const LocalChunkData, lx: i32, ly: i32, lz: i32) u8 {
        const x_idx = lx + 1;
        const y_idx = ly + 1;
        const z_idx = lz + 1;
        if (x_idx < 0 or x_idx >= 18 or y_idx < 0 or y_idx >= 18 or z_idx < 0 or z_idx >= 18) return 0;
        return self.blocks[@intCast((x_idx * 18 + z_idx) * 18 + y_idx)];
    }
};

// ---------------------------------------------------------------------------
// SkyVertex – position-only
// ---------------------------------------------------------------------------
const SkyVertex = extern struct { x: f32, y: f32, z: f32 };

// ---------------------------------------------------------------------------
// CloudVertex – position + uv
// ---------------------------------------------------------------------------
const CloudVertex = extern struct { x: f32, y: f32, z: f32, u: f32, v: f32 };

// ---------------------------------------------------------------------------
// LevelRenderer
// ---------------------------------------------------------------------------

pub const LevelRenderer = struct {
    alloc: std.mem.Allocator,
    context: *ctx.VkContext,
    pipelines: pip.Pipelines,
    level_source: *rls.RandomLevelSource,

    io: std.Io,
    level_mutex: std.Io.Mutex = std.Io.Mutex.init,
    rebuild_group: std.Io.Group = .init,
    completed_queue: std.Io.Queue(RebuildResult),
    completed_buffer: []RebuildResult,
    active_rebuilds: usize = 0,

    // ---- Chunk grid (mirrors C++ xChunks/yChunks/zChunks / chunks[] ) ---
    x_chunks: i32 = 0,
    y_chunks: i32 = 0,
    z_chunks: i32 = 0,
    chunks: []ChunkSlot,
    sorted_indices: []usize, // indices into chunks[], sorted by distance
    buffer_pool: VulkanBufferPool,

    // ---- Player camera position (interpolated) ---
    cam_x: f32 = 0,
    cam_y: f32 = 0,
    cam_z: f32 = 0,

    /// Old camera pos for resort-trigger
    old_x: f32 = -9999,
    old_y: f32 = -9999,
    old_z: f32 = -9999,

    // ---- Per-frame UBO buffers (one per MAX_FRAMES_IN_FLIGHT) ---
    ubo_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer,

    // ---- Sky ---
    sky_vbuf: gpu.GpuBuffer,
    sky_vertex_count: u32 = 0,
    sky_ubo_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer,
    sky_color_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer,

    // ---- Clouds ---
    cloud_vbuf: gpu.GpuBuffer,
    cloud_ubo_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer,
    cloud_color_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer,

    // ---- Descriptor pools / sets ---
    desc_pool: vk.VkDescriptorPool,
    /// terrain UBO sets [frame][chunk_index] – simplified: one set per frame
    ubo_sets: [ctx.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet,
    sky_sets: [ctx.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet,
    cloud_sets: [ctx.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet,

    tex_image: vk.VkImage = 0,
    tex_memory: vk.VkDeviceMemory = 0,
    tex_view: vk.VkImageView = 0,
    tex_sampler: vk.VkSampler = 0,
    tex_set: vk.VkDescriptorSet = 0,

    /// Monotonically increasing tick counter.
    ticks: u32 = 0,

    /// Player is mid-rebuild cycle (matches C++ noEntityRenderFrames)
    no_entity_frames: u32 = 2,

    // -----------------------------------------------------------------------
    // init / deinit
    // -----------------------------------------------------------------------

    pub fn init(
        alloc: std.mem.Allocator,
        context: *ctx.VkContext,
        level_source: *rls.RandomLevelSource,
        view_distance: u32,
        io: std.Io,
    ) !LevelRenderer {
        const completed_buffer = try alloc.alloc(RebuildResult, 256);
        errdefer alloc.free(completed_buffer);
        const completed_queue = std.Io.Queue(RebuildResult).init(completed_buffer);

        const pipelines = try pip.createAll(
            context.vf,
            context.device,
            context.render_pass,
        );

        // Build chunk grid dimensions from view distance (mirrors C++ allChanged)
        const dist: i32 = dist: {
            const shift: u5 = @intCast(4 - @min(view_distance, @as(u32, 4)));
            const d: i32 = @as(i32, 512 >> 3) << shift;
            break :dist @min(d, 400);
        };
        const xc: i32 = @divTrunc(dist, CHUNK_SIZE) + 1;
        const yc: i32 = @divTrunc(128, CHUNK_SIZE);
        const zc: i32 = @divTrunc(dist, CHUNK_SIZE) + 1;
        const total: usize = @intCast(xc * yc * zc);

        const chunks = try alloc.alloc(ChunkSlot, total);
        const sorted = try alloc.alloc(usize, total);
        const buffer_pool = VulkanBufferPool.init(alloc, context, CHUNK_ARENA_BYTES);

        // Initialize chunk slots using linearIdx
        {
            var sz: i32 = 0;
            while (sz < zc) : (sz += 1) {
                var sy: i32 = 0;
                while (sy < yc) : (sy += 1) {
                    var sx: i32 = 0;
                    while (sx < xc) : (sx += 1) {
                        const idx = linearIdx(@intCast(sx), @intCast(sy), @intCast(sz), @intCast(xc), @intCast(yc));
                        chunks[idx] = ChunkSlot{
                            .x = sx * CHUNK_SIZE,
                            .y = sy * CHUNK_SIZE,
                            .z = sz * CHUNK_SIZE,
                            .id = @intCast(idx),
                        };
                        sorted[idx] = idx;
                    }
                }
            }
        }

        // Allocate per-chunk VBOs for each layer
        // DISABLED: KosmicKrisp maxMemoryAllocationCount is 4096 and
        // the Metal driver reserves most of them internally.
        // Chunk VBOs will be allocated lazily when chunks are built.
        // for (chunks) |*slot| {
        //     for (&slot.layers) |*layer| {
        //         layer.vbuf = try gpu.GpuBuffer.init(context, CHUNK_VBUF_BYTES, vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        //         layer.dirty = true;
        //         layer.empty = true;
        //     }
        // }
        // Initialize all chunk layers as empty (no VBO yet).
        @memset(@as([*]u8, @ptrCast(chunks.ptr))[0 .. @sizeOf(ChunkSlot) * chunks.len], 0);
        for (chunks) |*slot| {
            slot.visible = true;
            for (&slot.layers) |*layer| {
                layer.dirty = true;
                layer.empty = true;
            }
        }

        // UBO buffers
        var ubo_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer = undefined;
        var sky_ubo_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer = undefined;
        var sky_color_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer = undefined;
        var cloud_ubo_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer = undefined;
        var cloud_color_buf: [ctx.MAX_FRAMES_IN_FLIGHT]gpu.GpuBuffer = undefined;

        for (0..ctx.MAX_FRAMES_IN_FLIGHT) |i| {
            ubo_buf[i] = try gpu.GpuBuffer.init(context, @sizeOf(UboData), vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
            sky_ubo_buf[i] = try gpu.GpuBuffer.init(context, @sizeOf(UboData), vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
            sky_color_buf[i] = try gpu.GpuBuffer.init(context, @sizeOf(SkyColorData), vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
            cloud_ubo_buf[i] = try gpu.GpuBuffer.init(context, @sizeOf(UboData), vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
            cloud_color_buf[i] = try gpu.GpuBuffer.init(context, @sizeOf(CloudColorData), vk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT);
        }

        // Sky geometry (static, generated once)
        var sky_vbuf = try gpu.GpuBuffer.init(context, 4 * 1024 * 1024, vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);
        const sky_vcount = try generateSkyGeometry(context, &sky_vbuf);

        // Cloud geometry (dynamic each frame – allocate a large enough buffer)
        const cloud_vbuf = try gpu.GpuBuffer.init(context, 4 * 1024 * 1024, vk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT);

        // Descriptor pool
        const pool_sizes = [_]vk.VkDescriptorPoolSize{
            .{ .type = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 128 },
            .{ .type = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, .descriptorCount = 32 },
        };
        const pool_ci = vk.VkDescriptorPoolCreateInfo{
            .sType = 33,
            .maxSets = 64,
            .poolSizeCount = pool_sizes.len,
            .pPoolSizes = &pool_sizes,
        };
        var desc_pool: vk.VkDescriptorPool = 0;
        const r = context.vf.vkCreateDescriptorPool(context.device, &pool_ci, null, &desc_pool);
        if (r != vk.VK_SUCCESS) return error.DescPoolCreateFailed;

        // ---- Load terrain texture ----
        const terrain_img = try png.loadPng(alloc, "data/images/terrain.png");
        defer terrain_img.deinit(alloc);

        var staging_buf: vk.VkBuffer = 0;
        var staging_mem: vk.VkDeviceMemory = 0;
        try context.createBuffer(
            terrain_img.pixels.len,
            vk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &staging_buf,
            &staging_mem,
        );
        defer {
            context.vf.vkDestroyBuffer(context.device, staging_buf, null);
            context.vf.vkFreeMemory(context.device, staging_mem, null);
        }

        try context.uploadToBuffer(staging_mem, terrain_img.pixels);

        var tex_image: vk.VkImage = 0;
        var tex_memory: vk.VkDeviceMemory = 0;
        try ctx.createImage(
            context.vf,
            context.device,
            context.mem_props,
            terrain_img.width,
            terrain_img.height,
            vk.VK_FORMAT_R8G8B8A8_UNORM,
            vk.VK_IMAGE_TILING_OPTIMAL,
            vk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | vk.VK_IMAGE_USAGE_SAMPLED_BIT,
            vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            &tex_image,
            &tex_memory,
        );

        // Transition image and copy buffer to image
        const cb = try context.beginOneShot();

        const barrier1 = vk.VkImageMemoryBarrier{
            .sType = 45,
            .oldLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = tex_image,
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcAccessMask = 0,
            .dstAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
        };
        context.vf.vkCmdPipelineBarrier(
            cb,
            vk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            @as([*]const vk.VkImageMemoryBarrier, @ptrCast(&barrier1)),
        );

        const region = vk.VkBufferImageCopy{
            .bufferOffset = 0,
            .bufferRowLength = 0,
            .bufferImageHeight = 0,
            .imageSubresource = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .mipLevel = 0,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
            .imageExtent = .{ .width = terrain_img.width, .height = terrain_img.height, .depth = 1 },
        };
        context.vf.vkCmdCopyBufferToImage(
            cb,
            staging_buf,
            tex_image,
            vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            @as([*]const vk.VkBufferImageCopy, @ptrCast(&region)),
        );

        const barrier2 = vk.VkImageMemoryBarrier{
            .sType = 45,
            .oldLayout = vk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = vk.VK_QUEUE_FAMILY_IGNORED,
            .image = tex_image,
            .subresourceRange = .{
                .aspectMask = vk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcAccessMask = vk.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = vk.VK_ACCESS_SHADER_READ_BIT,
        };
        context.vf.vkCmdPipelineBarrier(
            cb,
            vk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            vk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0,
            0,
            null,
            0,
            null,
            1,
            @as([*]const vk.VkImageMemoryBarrier, @ptrCast(&barrier2)),
        );

        try context.endOneShot(cb);

        const tex_view = try ctx.createImageView(
            context.vf,
            context.device,
            tex_image,
            vk.VK_FORMAT_R8G8B8A8_UNORM,
            vk.VK_IMAGE_ASPECT_COLOR_BIT,
        );

        const sampler_ci = vk.VkSamplerCreateInfo{
            .sType = 31,
            .magFilter = vk.VK_FILTER_NEAREST,
            .minFilter = vk.VK_FILTER_NEAREST,
            .mipmapMode = vk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
            .addressModeU = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeV = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .addressModeW = vk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE,
            .anisotropyEnable = 0,
            .maxAnisotropy = 1.0,
            .compareEnable = 0,
            .compareOp = vk.VK_COMPARE_OP_ALWAYS,
            .minLod = 0.0,
            .maxLod = 0.0,
            .borderColor = vk.VK_BORDER_COLOR_INT_OPAQUE_BLACK,
            .unnormalizedCoordinates = 0,
        };
        var tex_sampler: vk.VkSampler = 0;
        const r_sampler = context.vf.vkCreateSampler(context.device, &sampler_ci, null, &tex_sampler);
        if (r_sampler != vk.VK_SUCCESS) return error.SamplerCreateFailed;

        // Allocate texture descriptor set
        const tex_layout = pipelines.terrain_opaque.dset_layout_tex;
        var tex_set: vk.VkDescriptorSet = 0;
        const ai_tex = vk.VkDescriptorSetAllocateInfo{
            .sType = 34,
            .descriptorPool = desc_pool,
            .descriptorSetCount = 1,
            .pSetLayouts = &[_]vk.VkDescriptorSetLayout{tex_layout},
        };
        const r_tex = context.vf.vkAllocateDescriptorSets(context.device, &ai_tex, @as([*]vk.VkDescriptorSet, @ptrCast(&tex_set)));
        if (r_tex != vk.VK_SUCCESS) return error.DescSetAllocFailed;

        // Write texture descriptor set
        const image_info = vk.VkDescriptorImageInfo{
            .sampler = tex_sampler,
            .imageView = tex_view,
            .imageLayout = vk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        };
        const write_tex = vk.VkWriteDescriptorSet{
            .sType = 35,
            .dstSet = tex_set,
            .dstBinding = 0,
            .descriptorCount = 1,
            .descriptorType = vk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .pImageInfo = @as([*]const vk.VkDescriptorImageInfo, @ptrCast(&image_info)),
        };
        context.vf.vkUpdateDescriptorSets(context.device, 1, &[_]vk.VkWriteDescriptorSet{write_tex}, 0, null);

        // Allocate UBO descriptor sets per frame
        var ubo_sets: [ctx.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = undefined;
        var sky_sets: [ctx.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = undefined;
        var cloud_sets: [ctx.MAX_FRAMES_IN_FLIGHT]vk.VkDescriptorSet = undefined;
        for (0..ctx.MAX_FRAMES_IN_FLIGHT) |i| {
            ubo_sets[i] = try allocDescSet(context, desc_pool, pipelines.terrain_opaque.dset_layout_ubo);
            sky_sets[i] = try allocDescSet(context, desc_pool, pipelines.sky.dset_layout_ubo);
            cloud_sets[i] = try allocDescSet(context, desc_pool, pipelines.clouds.dset_layout_ubo);
            // Write UBO bindings
            writeUboSet(context, ubo_sets[i], ubo_buf[i].buf, @sizeOf(UboData));
            writeSkySet(context, sky_sets[i], sky_ubo_buf[i].buf, sky_color_buf[i].buf);
            writeCloudSet(context, cloud_sets[i], cloud_ubo_buf[i].buf, cloud_color_buf[i].buf);
        }

        std.debug.print("init: {d} chunks\n", .{total});

        return .{
            .alloc = alloc,
            .context = context,
            .pipelines = pipelines,
            .level_source = level_source,
            .io = io,
            .completed_buffer = completed_buffer,
            .completed_queue = completed_queue,
            .x_chunks = xc,
            .y_chunks = yc,
            .z_chunks = zc,
            .chunks = chunks,
            .sorted_indices = sorted,
            .buffer_pool = buffer_pool,
            .ubo_buf = ubo_buf,
            .sky_vbuf = sky_vbuf,
            .sky_vertex_count = sky_vcount,
            .sky_ubo_buf = sky_ubo_buf,
            .sky_color_buf = sky_color_buf,
            .cloud_vbuf = cloud_vbuf,
            .cloud_ubo_buf = cloud_ubo_buf,
            .cloud_color_buf = cloud_color_buf,
            .desc_pool = desc_pool,
            .ubo_sets = ubo_sets,
            .sky_sets = sky_sets,
            .cloud_sets = cloud_sets,
            .tex_image = tex_image,
            .tex_memory = tex_memory,
            .tex_view = tex_view,
            .tex_sampler = tex_sampler,
            .tex_set = tex_set,
        };
    }

    pub fn deinit(self: *LevelRenderer) void {
        self.completed_queue.close(self.io);
        self.rebuild_group.cancel(self.io);
        _ = self.rebuild_group.await(self.io) catch {};

        var completed_rebuilds: [32]RebuildResult = undefined;
        while (true) {
            const count = self.completed_queue.get(self.io, &completed_rebuilds, 0) catch 0;
            if (count == 0) break;
            for (completed_rebuilds[0..count]) |res| {
                for (res.layers) |l| {
                    if (l.verts.len > 0) self.alloc.free(l.verts);
                }
            }
        }
        self.alloc.free(self.completed_buffer);

        _ = self.context.vf.vkDeviceWaitIdle(self.context.device);

        self.context.vf.vkDestroyDescriptorPool(self.context.device, self.desc_pool, null);

        self.context.vf.vkDestroySampler(self.context.device, self.tex_sampler, null);
        self.context.vf.vkDestroyImageView(self.context.device, self.tex_view, null);
        self.context.vf.vkDestroyImage(self.context.device, self.tex_image, null);
        self.context.vf.vkFreeMemory(self.context.device, self.tex_memory, null);

        for (0..ctx.MAX_FRAMES_IN_FLIGHT) |i| {
            self.ubo_buf[i].deinit(self.context.vf, self.context.device);
            self.sky_ubo_buf[i].deinit(self.context.vf, self.context.device);
            self.sky_color_buf[i].deinit(self.context.vf, self.context.device);
            self.cloud_ubo_buf[i].deinit(self.context.vf, self.context.device);
            self.cloud_color_buf[i].deinit(self.context.vf, self.context.device);
        }

        self.sky_vbuf.deinit(self.context.vf, self.context.device);
        self.cloud_vbuf.deinit(self.context.vf, self.context.device);

        self.buffer_pool.deinit();

        self.alloc.free(self.chunks);
        self.alloc.free(self.sorted_indices);

        pip.destroyAll(self.context.vf, self.context.device, &self.pipelines);
    }

    // -----------------------------------------------------------------------
    // tick – called once per game tick (20 Hz)
    // -----------------------------------------------------------------------
    pub fn tick(self: *LevelRenderer) void {
        self.ticks += 1;
    }

    // -----------------------------------------------------------------------
    // tileChanged / setDirty  (mirrors C++ setDirty / tileChanged)
    // -----------------------------------------------------------------------

    pub fn tileChanged(self: *LevelRenderer, x: i32, y: i32, z: i32) void {
        self.setDirty(x - 1, y - 1, z - 1, x + 1, y + 1, z + 1);
    }

    pub fn setTilesDirty(self: *LevelRenderer, x0: i32, y0: i32, z0: i32, x1: i32, y1: i32, z1: i32) void {
        self.setDirty(x0 - 1, y0 - 1, z0 - 1, x1 + 1, y1 + 1, z1 + 1);
    }

    pub fn setDirty(self: *LevelRenderer, x0: i32, y0: i32, z0: i32, x1: i32, y1: i32, z1: i32) void {
        const cx0 = floorDiv(x0, CHUNK_SIZE);
        const cy0 = floorDiv(y0, CHUNK_SIZE);
        const cz0 = floorDiv(z0, CHUNK_SIZE);
        const cx1 = floorDiv(x1, CHUNK_SIZE);
        const cy1 = floorDiv(y1, CHUNK_SIZE);
        const cz1 = floorDiv(z1, CHUNK_SIZE);

        var cx = cx0;
        while (cx <= cx1) : (cx += 1) {
            const xx: usize = @intCast(@mod(cx, self.x_chunks));
            var cy = cy0;
            while (cy <= cy1) : (cy += 1) {
                const yy: usize = @intCast(@mod(cy, self.y_chunks));
                var cz = cz0;
                while (cz <= cz1) : (cz += 1) {
                    const zz: usize = @intCast(@mod(cz, self.z_chunks));
                    const idx = linearIdx(xx, yy, zz, @intCast(self.x_chunks), @intCast(self.y_chunks));
                    const slot = &self.chunks[idx];
                    if (!slot.dirty) {
                        slot.setDirty();
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // updateDirtyChunks  (mirrors C++ updateDirtyChunks)
    // -----------------------------------------------------------------------

    pub fn updateDirtyChunks(self: *LevelRenderer, cam_x: f32, cam_y: f32, cam_z: f32, force: bool) bool {
        _ = cam_x;
        _ = cam_y;
        _ = cam_z;

        const close_radius_sq: f32 = 32 * 32;
        var built_visible: usize = 0;
        var built_hidden: usize = 0;
        var all_clean = true;

        for (self.sorted_indices) |idx| {
            const slot = &self.chunks[idx];
            if (!slot.dirty) continue;

            if (slot.rebuilding) {
                all_clean = false;
                continue;
            }

            const d = slot.distSqr(self.cam_x, self.cam_y, self.cam_z);

            if (!force) {
                if (d > close_radius_sq) {
                    if (slot.visible) {
                        if (built_visible >= MAX_VISIBLE_REBUILDS_PER_FRAME) {
                            all_clean = false;
                            continue;
                        }
                        built_visible += 1;
                    } else {
                        if (built_hidden >= MAX_INVISIBLE_REBUILDS_PER_FRAME) {
                            all_clean = false;
                            continue;
                        }
                        built_hidden += 1;
                    }
                }
            } else if (!slot.visible) {
                all_clean = false;
                continue;
            }

            if (self.active_rebuilds >= 16) {
                all_clean = false;
                continue;
            }

            slot.rebuilding = true;
            self.active_rebuilds += 1;

            self.rebuild_group.concurrent(self.io, backgroundRebuildTask, .{ self, idx, slot.x, slot.y, slot.z, self.io }) catch |err| {
                std.debug.print("Failed to spawn rebuild task for slot {d}: {}\n", .{ idx, err });
                slot.rebuilding = false;
                self.active_rebuilds -= 1;
                all_clean = false;
            };
        }

        return all_clean;
    }

    // -----------------------------------------------------------------------
    // resortChunks  (mirrors C++ resortChunks)
    // -----------------------------------------------------------------------

    pub fn resortChunks(self: *LevelRenderer, px: f32, py: f32, pz: f32) void {
        self.cam_x = px;
        self.cam_y = py;
        self.cam_z = pz;

        // Re-assign world positions using wrapping (mirrors C++ torus scrolling)
        const sx2: f32 = @as(f32, @floatFromInt(self.x_chunks)) * CHUNK_SIZE;
        const sx1: f32 = sx2 / 2.0;
        const sz2: f32 = @as(f32, @floatFromInt(self.z_chunks)) * CHUNK_SIZE;
        const sz1: f32 = sz2 / 2.0;
        const xc = self.x_chunks;
        const yc = self.y_chunks;
        const zc = self.z_chunks;

        var xi: i32 = 0;
        while (xi < xc) : (xi += 1) {
            var xx = xi * CHUNK_SIZE;
            var xoff = (xx + @as(i32, @intFromFloat(sx1)) - @as(i32, @intFromFloat(px)));
            if (xoff < 0) xoff -= (@as(i32, @intFromFloat(sx2)) - 1);
            xoff = @divTrunc(xoff, @as(i32, @intFromFloat(sx2)));
            xx -= xoff * @as(i32, @intFromFloat(sx2));

            var zi: i32 = 0;
            while (zi < zc) : (zi += 1) {
                var zz = zi * CHUNK_SIZE;
                var zoff = (zz + @as(i32, @intFromFloat(sz1)) - @as(i32, @intFromFloat(pz)));
                if (zoff < 0) zoff -= (@as(i32, @intFromFloat(sz2)) - 1);
                zoff = @divTrunc(zoff, @as(i32, @intFromFloat(sz2)));
                zz -= zoff * @as(i32, @intFromFloat(sz2));

                var yi: i32 = 0;
                while (yi < yc) : (yi += 1) {
                    const yy = yi * CHUNK_SIZE;
                    const flat = linearIdx(@intCast(xi), @intCast(yi), @intCast(zi), @intCast(xc), @intCast(yc));
                    const slot = &self.chunks[flat];
                    const was_dirty = slot.dirty;
                    slot.x = xx;
                    slot.y = yy;
                    slot.z = zz;
                    if (!was_dirty) {
                        slot.setDirty();
                    }
                }
            }
        }

        // Sort sorted_indices by distance to camera
        const Self = @This();
        std.mem.sort(usize, self.sorted_indices, self, struct {
            fn lt(lr: *Self, a: usize, b: usize) bool {
                return lr.chunks[a].distSqr(lr.cam_x, lr.cam_y, lr.cam_z) <
                    lr.chunks[b].distSqr(lr.cam_x, lr.cam_y, lr.cam_z);
            }
        }.lt);
    }

    // -----------------------------------------------------------------------
    // render  (mirrors C++ LevelRenderer::render)
    // Called once per layer (0 = opaque, 1 = alpha-test, 2 = water)
    // -----------------------------------------------------------------------

    pub fn render(
        self: *LevelRenderer,
        cmd: vk.VkCommandBuffer,
        layer: usize,
        mvp: Mat4,
    ) !void {
        const frame = self.context.frame_index;

        // Choose pipeline
        const pipe = switch (layer) {
            0 => &self.pipelines.terrain_opaque,
            1 => &self.pipelines.terrain_alpha,
            2 => &self.pipelines.terrain_blend,
            else => return,
        };

        var current_frame_ubo = UboData{
            .mvp = undefined,
            .offset = .{ self.cam_x, self.cam_y, self.cam_z },
        };

        zm.storeMat(&current_frame_ubo.mvp, mvp);

        try self.ubo_buf[frame].uploadUbo(self.context, current_frame_ubo);

        self.context.vf.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipe.pipeline);
        self.context.vf.vkCmdBindDescriptorSets(
            cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipe.layout,
            0,
            2,
            &[_]vk.VkDescriptorSet{ self.ubo_sets[frame], self.tex_set },
            0,
            null,
        );

        // Draw each visible chunk layer
        for (self.sorted_indices) |idx| {
            const slot = &self.chunks[idx];
            if (!slot.visible) continue;
            const chunk_layer = &slot.layers[layer];
            if (chunk_layer.empty or chunk_layer.vertex_count == 0 or chunk_layer.vbuf_alloc == null) continue;

            const alloc_info = chunk_layer.vbuf_alloc.?;
            const offsets = [_]vk.VkDeviceSize{alloc_info.offset};
            self.context.vf.vkCmdBindVertexBuffers(cmd, 0, 1, &[_]vk.VkBuffer{alloc_info.buffer}, &offsets);
            self.context.vf.vkCmdDraw(cmd, chunk_layer.vertex_count, 1, 0, 0);
        }
    }

    // -----------------------------------------------------------------------
    // renderSky  (mirrors C++ LevelRenderer::renderSky)
    //
    // The C++ version drew a grid of quads at y=16 above the player using a
    // pre-baked VBO.  We do the same: generate once in init, draw every frame.
    // Sky colour is passed in (computed by Level::getSkyColor in the game).
    // -----------------------------------------------------------------------

    pub fn renderSky(
        self: *LevelRenderer,
        cmd: vk.VkCommandBuffer,
        mvp: Mat4,
        sky_r: f32,
        sky_g: f32,
        sky_b: f32,
    ) void {
        const frame = self.context.frame_index;

        // p = vert - offset is in world space.
        // offset.y = -(cam_y + SKY_Y_OFFSET) → sky at world y = cam_y + 16
        // After view matrix: eye-space y = 16 (above camera).
        var current_frame_ubo = UboData{
            .mvp = undefined,
            .offset = .{ self.cam_x, -(self.cam_y + SKY_Y_OFFSET), self.cam_z },
        };
        zm.storeMat(&current_frame_ubo.mvp, mvp);

        self.context.uploadToBuffer(self.sky_ubo_buf[frame].mem, std.mem.asBytes(&current_frame_ubo)) catch return;

        // Sky colour uniform
        const sc = SkyColorData{ .color = .{ sky_r, sky_g, sky_b, 1.0 } };
        self.context.uploadToBuffer(self.sky_color_buf[frame].mem, std.mem.asBytes(&sc)) catch return;

        const pipe = &self.pipelines.sky;
        self.context.vf.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipe.pipeline);
        self.context.vf.vkCmdBindDescriptorSets(
            cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipe.layout,
            0,
            1,
            &[_]vk.VkDescriptorSet{self.sky_sets[frame]},
            0,
            null,
        );

        const offsets = [_]vk.VkDeviceSize{0};
        self.context.vf.vkCmdBindVertexBuffers(cmd, 0, 1, &[_]vk.VkBuffer{self.sky_vbuf.buf}, &offsets);
        self.context.vf.vkCmdDraw(cmd, self.sky_vertex_count, 1, 0, 0);
    }

    // -----------------------------------------------------------------------
    // renderClouds  (mirrors C++ LevelRenderer::renderClouds)
    //
    // A scrolling grid of quads textured with clouds.png.  The UVs scroll
    // based on ticks+alpha * 0.03.  We rebuild the vertex buffer every frame
    // because the UVs change (exactly as the C++ code called t.begin() /
    // t.endOverrideAndDraw() every frame).
    // -----------------------------------------------------------------------

    pub fn renderClouds(
        self: *LevelRenderer,
        alloc: std.mem.Allocator,
        cmd: vk.VkCommandBuffer,
        mvp: Mat4,
        alpha: f32,
        player_y: f32,
        player_x: f32,
        player_z: f32,
        cloud_r: f32,
        cloud_g: f32,
        cloud_b: f32,
    ) void {
        const frame = self.context.frame_index;

        // Cloud verts are built in camera-local space (xx,zz centred on 0).
        // offset=(0,0,0): view matrix handles translation.
        var current_frame_ubo = UboData{
            .mvp = undefined,
            .offset = .{ 0, 0, 0 },
        };
        zm.storeMat(&current_frame_ubo.mvp, mvp);
        self.context.uploadToBuffer(self.cloud_ubo_buf[frame].mem, std.mem.asBytes(&current_frame_ubo)) catch return;

        // Cloud colour
        const cc = CloudColorData{ .color = .{ cloud_r, cloud_g, cloud_b, 0.8 } };
        self.context.uploadToBuffer(self.cloud_color_buf[frame].mem, std.mem.asBytes(&cc)) catch return;

        // Rebuild cloud geometry (mirrors C++ renderClouds body)
        const time = @as(f32, @floatFromInt(self.ticks)) + alpha;
        const scale: f32 = 1.0 / 2048.0;

        var xo_raw = player_x + time * 0.03;
        var zo_raw = player_z;
        const xoffs = @floor(xo_raw / 2048.0);
        const zoffs = @floor(zo_raw / 2048.0);
        xo_raw -= xoffs * 2048.0;
        zo_raw -= zoffs * 2048.0;

        const yy = 128.0 - player_y + 0.33;
        const uo = xo_raw * scale;
        const vo = zo_raw * scale;

        const s: i32 = @intFromFloat(CLOUD_SEG);
        const d: i32 = CLOUD_DIVS;

        // Build vertex list
        var verts = std.ArrayListUnmanaged(CloudVertex).empty;
        defer verts.deinit(alloc);

        var xx: i32 = -s * d;
        while (xx < s * d) : (xx += s) {
            var zz: i32 = -s * d;
            while (zz < s * d) : (zz += s) {
                const fxx: f32 = @floatFromInt(xx);
                const fzz: f32 = @floatFromInt(zz);
                const fs: f32 = @floatFromInt(s);
                // One quad → 2 triangles (CCW winding)
                // v0 v1 v2  v0 v2 v3
                const v0 = CloudVertex{ .x = fxx, .y = yy, .z = fzz + fs, .u = fxx * scale + uo, .v = (fzz + fs) * scale + vo };
                const v1 = CloudVertex{ .x = fxx + fs, .y = yy, .z = fzz + fs, .u = (fxx + fs) * scale + uo, .v = (fzz + fs) * scale + vo };
                const v2 = CloudVertex{ .x = fxx + fs, .y = yy, .z = fzz, .u = (fxx + fs) * scale + uo, .v = fzz * scale + vo };
                const v3 = CloudVertex{ .x = fxx, .y = yy, .z = fzz, .u = fxx * scale + uo, .v = fzz * scale + vo };
                verts.appendSlice(alloc, &.{ v0, v1, v2, v0, v2, v3 }) catch return;
            }
        }

        // Upload to GPU buffer
        const bytes = std.mem.sliceAsBytes(verts.items);
        if (bytes.len > self.cloud_vbuf.capacity) return; // too many clouds
        self.context.uploadToBuffer(self.cloud_vbuf.mem, bytes) catch return;
        const vcount: u32 = @intCast(verts.items.len);

        // Draw
        const pipe = &self.pipelines.clouds;
        self.context.vf.vkCmdBindPipeline(cmd, vk.VK_PIPELINE_BIND_POINT_GRAPHICS, pipe.pipeline);
        self.context.vf.vkCmdBindDescriptorSets(
            cmd,
            vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
            pipe.layout,
            0,
            1,
            &[_]vk.VkDescriptorSet{self.cloud_sets[frame]},
            0,
            null,
        );
        const offsets = [_]vk.VkDeviceSize{0};
        self.context.vf.vkCmdBindVertexBuffers(cmd, 0, 1, &[_]vk.VkBuffer{self.cloud_vbuf.buf}, &offsets);
        self.context.vf.vkCmdDraw(cmd, vcount, 1, 0, 0);
    }

    // -----------------------------------------------------------------------
    // recordFrame
    // High-level helper: begin render pass, set viewport/scissor, call
    // renderSky + renderClouds + render (layers 0/1/2).
    //
    // In the full game integration this is called from GameRenderer::renderLevel.
    // -----------------------------------------------------------------------

    pub fn recordFrame(
        self: *LevelRenderer,
        alloc: std.mem.Allocator,
        image_index: u32,
        fov: f32,
        aspect: f32,
        near: f32,
        far: f32,
        view: Mat4,
        sky_color: [3]f32,
        cloud_color: [3]f32,
        player_x: f32,
        player_y: f32,
        player_z: f32,
        alpha: f32,
    ) !void {
        // Periodically resort chunks or if camera moved significantly
        const dx = player_x - self.old_x;
        const dy = player_y - self.old_y;
        const dz = player_z - self.old_z;
        if (dx * dx + dy * dy + dz * dz > 16.0 or self.old_x == -9999) {
            self.resortChunks(player_x, player_y, player_z);
            self.old_x = player_x;
            self.old_y = player_y;
            self.old_z = player_z;
        }

        // Update a few dirty chunks
        _ = self.updateDirtyChunks(player_x, player_y, player_z, false);

        // Poll completed rebuild tasks from queue (non-blocking)
        var completed_rebuilds: [32]RebuildResult = undefined;
        while (true) {
            const count = self.completed_queue.get(self.io, &completed_rebuilds, 0) catch 0;
            if (count == 0) break;

            for (completed_rebuilds[0..count]) |res| {
                self.active_rebuilds -= 1;
                const slot = &self.chunks[res.slot_idx];

                if (slot.x != res.expected_x or slot.y != res.expected_y or slot.z != res.expected_z) {
                    for (res.layers) |l| {
                        if (l.verts.len > 0) self.alloc.free(l.verts);
                    }
                    slot.setDirty();
                    slot.rebuilding = false;
                    continue;
                }

                for (res.layers, 0..) |res_layer, li| {
                    const layer = &slot.layers[li];
                    const verts = res_layer.verts;
                    if (verts.len > 0) {
                        const needed_bytes: vk.VkDeviceSize = @intCast(verts.len * @sizeOf(tss.Vertex));

                        if (layer.vbuf_alloc == null or layer.vbuf_alloc.?.size < needed_bytes) {
                            if (layer.vbuf_alloc) |alloc_info| {
                                self.buffer_pool.free(alloc_info);
                            }
                            layer.vbuf_alloc = try self.buffer_pool.allocate(needed_bytes, 64);
                        }

                        try uploadToBufferOffset(
                            self.context,
                            layer.vbuf_alloc.?.memory,
                            layer.vbuf_alloc.?.offset,
                            std.mem.sliceAsBytes(verts),
                        );
                        layer.vertex_count = @intCast(verts.len);
                        layer.dirty = false;
                        layer.empty = false;
                        self.alloc.free(verts);
                    } else {
                        if (layer.vbuf_alloc) |alloc_info| {
                            self.buffer_pool.free(alloc_info);
                            layer.vbuf_alloc = null;
                        }
                        layer.vertex_count = 0;
                        layer.empty = true;
                        layer.dirty = false;
                    }
                }
                slot.rebuilding = false;
                slot.setClean();
            }
        }

        // Update camera position used by chunk sorting and UBO offset
        self.cam_x = player_x;
        self.cam_y = player_y;
        self.cam_z = player_z;

        const cmd = self.context.frames[self.context.frame_index].cmd;
        const frame = self.context.frame_index;

        // Begin command buffer
        const bi = vk.VkCommandBufferBeginInfo{
            .sType = 42,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        var r = self.context.vf.vkBeginCommandBuffer(cmd, &bi);
        if (r != vk.VK_SUCCESS) return error.BeginCmdFailed;

        // Clear values
        const clears = [_]vk.VkClearValue{
            .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } }, // black for testing
            .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
        };
        const rp_bi = vk.VkRenderPassBeginInfo{
            .sType = 43,
            .renderPass = self.context.render_pass,
            .framebuffer = self.context.framebuffers[image_index],
            .renderArea = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.context.swap_extent,
            },
            .clearValueCount = clears.len,
            .pClearValues = &clears,
        };
        self.context.vf.vkCmdBeginRenderPass(cmd, &rp_bi, 0); // INLINE

        // Viewport + scissor (dynamic)
        const width: f32 = @floatFromInt(self.context.swap_extent.width);
        const height: f32 = @floatFromInt(self.context.swap_extent.height);
        // Standard Vulkan viewport (NDC y-down maps to screen top-to-bottom)
        const viewport = vk.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = width,
            .height = height,
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        const scissor = vk.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = self.context.swap_extent,
        };
        self.context.vf.vkCmdSetViewport(cmd, 0, 1, &[_]vk.VkViewport{viewport});
        self.context.vf.vkCmdSetScissor(cmd, 0, 1, &[_]vk.VkRect2D{scissor});

        // MVP = view * proj (row-major: view first, then project)
        const proj = zm.perspectiveFovRh(fov * math.pi / 180.0, aspect, near, far);
        const mvp = zm.mul(view, proj);

        // Sky
        self.renderSky(cmd, mvp, sky_color[0], sky_color[1], sky_color[2]);

        // Clouds - skip for now (texture set 1 not bound yet)
        self.renderClouds(alloc, cmd, mvp, alpha, player_y, player_x, player_z, cloud_color[0], cloud_color[1], cloud_color[2]);

        // Terrain layers
        try self.render(cmd, 0, mvp); // opaque
        try self.render(cmd, 1, mvp); // alpha-test
        try self.render(cmd, 2, mvp); // water

        self.context.vf.vkCmdEndRenderPass(cmd);

        r = self.context.vf.vkEndCommandBuffer(cmd);
        if (r != vk.VK_SUCCESS) return error.EndCmdFailed;

        _ = frame;
    }

    fn backgroundRebuildTask(
        self: *LevelRenderer,
        slot_idx: usize,
        expected_x: i32,
        expected_y: i32,
        expected_z: i32,
        io: std.Io,
    ) std.Io.Cancelable!void {
        // 1. Copy block data under lock
        var local_data: LocalChunkData = undefined;
        var col_blocks: [3][3]?[]u8 = undefined;
        {
            self.level_mutex.lockUncancelable(io);
            defer self.level_mutex.unlock(io);

            const cx = @divFloor(expected_x, 16);
            const cz = @divFloor(expected_z, 16);

            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                var dz: i32 = -1;
                while (dz <= 1) : (dz += 1) {
                    const col = self.level_source.getChunk(cx + dx, cz + dz) catch null;
                    col_blocks[@intCast(dx + 1)][@intCast(dz + 1)] = if (col) |c| c.blocks else null;
                }
            }
        }

        var lx: i32 = -1;
        while (lx <= 16) : (lx += 1) {
            const dx_idx: usize = if (lx == -1) 0 else if (lx == 16) 2 else 1;
            const bx: i32 = if (lx == -1) 15 else if (lx == 16) 0 else lx;

            var lz: i32 = -1;
            while (lz <= 16) : (lz += 1) {
                const dz_idx: usize = if (lz == -1) 0 else if (lz == 16) 2 else 1;
                const bz: i32 = if (lz == -1) 15 else if (lz == 16) 0 else lz;

                const blocks_opt = col_blocks[dx_idx][dz_idx];

                var ly: i32 = -1;
                while (ly <= 16) : (ly += 1) {
                    const gy = expected_y + ly;
                    const x_idx = lx + 1;
                    const y_idx = ly + 1;
                    const z_idx = lz + 1;

                    var block_id: u8 = 0;
                    if (gy >= 0 and gy < 128) {
                        if (blocks_opt) |blocks| {
                            block_id = blocks[chunk.blockOffset(bx, gy, bz)];
                        }
                    }
                    local_data.blocks[@intCast((x_idx * 18 + z_idx) * 18 + y_idx)] = block_id;
                }
            }
        }

        // 2. Perform CPU-heavy tessellation completely offline/unlocked
        var result = RebuildResult{
            .slot_idx = slot_idx,
            .expected_x = expected_x,
            .expected_y = expected_y,
            .expected_z = expected_z,
            .layers = undefined,
        };
        errdefer {
            for (result.layers) |l| {
                if (l.verts.len > 0) self.alloc.free(l.verts);
            }
        }

        inline for (0..NUM_LAYERS) |li| {
            var tessy = tss.Tesselator.init(self.alloc) catch |err| switch (err) {
                error.OutOfMemory => return,
            };
            defer tessy.deinit();

            tessy.beginMode(.quads);

            var bx: i32 = 0;
            while (bx < 16) : (bx += 1) {
                var bz: i32 = 0;
                while (bz < 16) : (bz += 1) {
                    var by: i32 = 0;
                    while (by < 16) : (by += 1) {
                        const block_id = local_data.getBlock(bx, by, bz);
                        if (block_id == 0) continue; // air

                        const layer = getBlockLayer(block_id) orelse continue;
                        if (layer != li) continue;

                        const fx = @as(f32, @floatFromInt(bx)) + @as(f32, @floatFromInt(expected_x));
                        const fy = @as(f32, @floatFromInt(by)) + @as(f32, @floatFromInt(expected_y));
                        const fz = @as(f32, @floatFromInt(bz)) + @as(f32, @floatFromInt(expected_z));

                        // Up (Y+)
                        if (isFaceVisible(block_id, local_data.getBlock(bx, by + 1, bz))) {
                            const col = getBlockColor(block_id, .up);
                            const tex_idx = getBlockTextureIndex(block_id, .up);
                            const tu0 = @as(f32, @floatFromInt(tex_idx % 16)) / 16.0;
                            const tv0 = @as(f32, @floatFromInt(tex_idx / 16)) / 16.0;
                            const tu1 = tu0 + 1.0 / 16.0;
                            const tv1 = tv0 + 1.0 / 16.0;

                            tessy.colorF(col[0], col[1], col[2], 1.0);
                            tessy.tex(tu0, tv1);
                            tessy.vertex(fx, fy + 1.0, fz + 1.0);
                            tessy.tex(tu0, tv0);
                            tessy.vertex(fx, fy + 1.0, fz);
                            tessy.tex(tu1, tv0);
                            tessy.vertex(fx + 1.0, fy + 1.0, fz);
                            tessy.tex(tu1, tv1);
                            tessy.vertex(fx + 1.0, fy + 1.0, fz + 1.0);
                        }
                        // Down (Y-)
                        if (isFaceVisible(block_id, local_data.getBlock(bx, by - 1, bz))) {
                            const col = getBlockColor(block_id, .down);
                            const tex_idx = getBlockTextureIndex(block_id, .down);
                            const tu0 = @as(f32, @floatFromInt(tex_idx % 16)) / 16.0;
                            const tv0 = @as(f32, @floatFromInt(tex_idx / 16)) / 16.0;
                            const tu1 = tu0 + 1.0 / 16.0;
                            const tv1 = tv0 + 1.0 / 16.0;

                            tessy.colorF(col[0], col[1], col[2], 1.0);
                            tessy.tex(tu0, tv0);
                            tessy.vertex(fx, fy, fz);
                            tessy.tex(tu0, tv1);
                            tessy.vertex(fx, fy, fz + 1.0);
                            tessy.tex(tu1, tv1);
                            tessy.vertex(fx + 1.0, fy, fz + 1.0);
                            tessy.tex(tu1, tv0);
                            tessy.vertex(fx + 1.0, fy, fz);
                        }
                        // North (Z-)
                        if (isFaceVisible(block_id, local_data.getBlock(bx, by, bz - 1))) {
                            const col = getBlockColor(block_id, .north);
                            const tex_idx = getBlockTextureIndex(block_id, .north);
                            const tu0 = @as(f32, @floatFromInt(tex_idx % 16)) / 16.0;
                            const tv0 = @as(f32, @floatFromInt(tex_idx / 16)) / 16.0;
                            const tu1 = tu0 + 1.0 / 16.0;
                            const tv1 = tv0 + 1.0 / 16.0;

                            tessy.colorF(col[0], col[1], col[2], 1.0);
                            tessy.tex(tu0, tv1);
                            tessy.vertex(fx, fy, fz);
                            tessy.tex(tu1, tv1);
                            tessy.vertex(fx + 1.0, fy, fz);
                            tessy.tex(tu1, tv0);
                            tessy.vertex(fx + 1.0, fy + 1.0, fz);
                            tessy.tex(tu0, tv0);
                            tessy.vertex(fx, fy + 1.0, fz);
                        }
                        // South (Z+)
                        if (isFaceVisible(block_id, local_data.getBlock(bx, by, bz + 1))) {
                            const col = getBlockColor(block_id, .south);
                            const tex_idx = getBlockTextureIndex(block_id, .south);
                            const tu0 = @as(f32, @floatFromInt(tex_idx % 16)) / 16.0;
                            const tv0 = @as(f32, @floatFromInt(tex_idx / 16)) / 16.0;
                            const tu1 = tu0 + 1.0 / 16.0;
                            const tv1 = tv0 + 1.0 / 16.0;

                            tessy.colorF(col[0], col[1], col[2], 1.0);
                            tessy.tex(tu1, tv1);
                            tessy.vertex(fx + 1.0, fy, fz + 1.0);
                            tessy.tex(tu0, tv1);
                            tessy.vertex(fx, fy, fz + 1.0);
                            tessy.tex(tu0, tv0);
                            tessy.vertex(fx, fy + 1.0, fz + 1.0);
                            tessy.tex(tu1, tv0);
                            tessy.vertex(fx + 1.0, fy + 1.0, fz + 1.0);
                        }
                        // West (X-)
                        if (isFaceVisible(block_id, local_data.getBlock(bx - 1, by, bz))) {
                            const col = getBlockColor(block_id, .west);
                            const tex_idx = getBlockTextureIndex(block_id, .west);
                            const tu0 = @as(f32, @floatFromInt(tex_idx % 16)) / 16.0;
                            const tv0 = @as(f32, @floatFromInt(tex_idx / 16)) / 16.0;
                            const tu1 = tu0 + 1.0 / 16.0;
                            const tv1 = tv0 + 1.0 / 16.0;

                            tessy.colorF(col[0], col[1], col[2], 1.0);
                            tessy.tex(tu0, tv1);
                            tessy.vertex(fx, fy, fz);
                            tessy.tex(tu0, tv0);
                            tessy.vertex(fx, fy + 1.0, fz);
                            tessy.tex(tu1, tv0);
                            tessy.vertex(fx, fy + 1.0, fz + 1.0);
                            tessy.tex(tu1, tv1);
                            tessy.vertex(fx, fy, fz + 1.0);
                        }
                        // East (X+)
                        if (isFaceVisible(block_id, local_data.getBlock(bx + 1, by, bz))) {
                            const col = getBlockColor(block_id, .east);
                            const tex_idx = getBlockTextureIndex(block_id, .east);
                            const tu0 = @as(f32, @floatFromInt(tex_idx % 16)) / 16.0;
                            const tv0 = @as(f32, @floatFromInt(tex_idx / 16)) / 16.0;
                            const tu1 = tu0 + 1.0 / 16.0;
                            const tv1 = tv0 + 1.0 / 16.0;

                            tessy.colorF(col[0], col[1], col[2], 1.0);
                            tessy.tex(tu0, tv1);
                            tessy.vertex(fx + 1.0, fy, fz + 1.0);
                            tessy.tex(tu0, tv0);
                            tessy.vertex(fx + 1.0, fy + 1.0, fz + 1.0);
                            tessy.tex(tu1, tv0);
                            tessy.vertex(fx + 1.0, fy + 1.0, fz);
                            tessy.tex(tu1, tv1);
                            tessy.vertex(fx + 1.0, fy, fz);
                        }
                    }
                }
            }

            const verts = tessy.finish();
            if (verts.len > 0) {
                const cloned = self.alloc.dupe(tss.Vertex, verts) catch |err| switch (err) {
                    error.OutOfMemory => return,
                };
                result.layers[li] = .{ .verts = cloned };
            } else {
                result.layers[li] = .{ .verts = &.{} };
            }
        }

        try io.checkCancel();

        self.completed_queue.putOne(io, result) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => return error.Canceled,
        };
    }

    pub fn getBlock(self: *LevelRenderer, x: i32, y: i32, z: i32) u8 {
        if (y < 0 or y >= 128) return 0;
        const cx = @divFloor(x, 16);
        const cz = @divFloor(z, 16);
        const level_chunk = self.level_source.getChunk(cx, cz) catch return 0;
        const bx = @as(i32, @intCast(@as(u32, @bitCast(x)) & 15));
        const bz = @as(i32, @intCast(@as(u32, @bitCast(z)) & 15));
        return level_chunk.blocks[chunk.blockOffset(bx, y, bz)];
    }
};

fn uploadToBufferOffset(
    context: *ctx.VkContext,
    buf_mem: vk.VkDeviceMemory,
    offset: vk.VkDeviceSize,
    data: []const u8,
) !void {
    var mapped: ?*anyopaque = null;
    const r = context.vf.vkMapMemory(context.device, buf_mem, offset, @intCast(data.len), 0, &mapped);
    if (r != vk.VK_SUCCESS) return error.MapMemoryFailed;
    @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..data.len], data);
    context.vf.vkUnmapMemory(context.device, buf_mem);
}

// ---------------------------------------------------------------------------
// generateSkyGeometry  (mirrors C++ LevelRenderer::generateSky)
//
// Builds a flat grid of quads at SKY_Y_OFFSET above the origin.
// The C++ version built quads and uploaded them as a VBO; we do the same but
// expand quads → triangles during generation so the buffer is draw-ready.
// ---------------------------------------------------------------------------

fn generateSkyGeometry(
    context: *ctx.VkContext,
    vbuf: *gpu.GpuBuffer,
) !u32 {
    const s: i32 = @intFromFloat(SKY_QUAD_SIZE);
    const d: i32 = (@as(i32, 256) / s) + 2;
    const yy: f32 = 0.0; // generated at y=0; UBO offset makes it cam_y+16

    var verts = std.ArrayList(SkyVertex).empty;
    defer verts.deinit(context.alloc);

    var xx: i32 = -s * d;
    while (xx <= s * d) : (xx += s) {
        var zz: i32 = -s * d;
        while (zz <= s * d) : (zz += s) {
            const fxx: f32 = @floatFromInt(xx);
            const fzz: f32 = @floatFromInt(zz);
            const fs: f32 = @floatFromInt(s);
            // quad: v0(xx,zz) v1(xx+s,zz) v2(xx+s,zz+s) v3(xx,zz+s)
            // triangles: v0 v1 v2  v0 v2 v3
            const v0 = SkyVertex{ .x = fxx, .y = yy, .z = fzz };
            const v1 = SkyVertex{ .x = fxx + fs, .y = yy, .z = fzz };
            const v2 = SkyVertex{ .x = fxx + fs, .y = yy, .z = fzz + fs };
            const v3 = SkyVertex{ .x = fxx, .y = yy, .z = fzz + fs };
            try verts.appendSlice(context.alloc, &.{ v0, v1, v2, v0, v2, v3 });
        }
    }

    const bytes = std.mem.sliceAsBytes(verts.items);
    try context.uploadToBuffer(vbuf.mem, bytes);
    vbuf.vertex_count = @intCast(verts.items.len);
    return vbuf.vertex_count;
}

// ---------------------------------------------------------------------------
// Descriptor set helpers
// ---------------------------------------------------------------------------

fn allocDescSet(
    context: *ctx.VkContext,
    pool: vk.VkDescriptorPool,
    layout: vk.VkDescriptorSetLayout,
) !vk.VkDescriptorSet {
    const ai = vk.VkDescriptorSetAllocateInfo{
        .sType = 34,
        .descriptorPool = pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &[_]vk.VkDescriptorSetLayout{layout},
    };
    var set: vk.VkDescriptorSet = 0;
    const r = context.vf.vkAllocateDescriptorSets(context.device, &ai, @as([*]vk.VkDescriptorSet, @ptrCast(&set)));
    if (r != vk.VK_SUCCESS) return error.DescSetAllocFailed;
    return set;
}

fn writeUboSet(
    context: *ctx.VkContext,
    set: vk.VkDescriptorSet,
    buf: vk.VkBuffer,
    size: vk.VkDeviceSize,
) void {
    const bi = vk.VkDescriptorBufferInfo{ .buffer = buf, .offset = 0, .range = size };
    const w = vk.VkWriteDescriptorSet{
        .sType = 35,
        .dstSet = set,
        .dstBinding = 0,
        .descriptorCount = 1,
        .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .pBufferInfo = @as([*]const vk.VkDescriptorBufferInfo, @ptrCast(&bi)),
    };
    context.vf.vkUpdateDescriptorSets(context.device, 1, &[_]vk.VkWriteDescriptorSet{w}, 0, null);
}

fn writeSkySet(
    context: *ctx.VkContext,
    set: vk.VkDescriptorSet,
    ubo_buf: vk.VkBuffer,
    color_buf: vk.VkBuffer,
) void {
    const bi0 = vk.VkDescriptorBufferInfo{ .buffer = ubo_buf, .offset = 0, .range = @sizeOf(UboData) };
    const bi1 = vk.VkDescriptorBufferInfo{ .buffer = color_buf, .offset = 0, .range = @sizeOf(SkyColorData) };
    const writes = [_]vk.VkWriteDescriptorSet{
        .{ .sType = 35, .dstSet = set, .dstBinding = 0, .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = @as([*]const vk.VkDescriptorBufferInfo, @ptrCast(&bi0)) },
        .{ .sType = 35, .dstSet = set, .dstBinding = 1, .descriptorCount = 1, .descriptorType = vk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = @as([*]const vk.VkDescriptorBufferInfo, @ptrCast(&bi1)) },
    };
    context.vf.vkUpdateDescriptorSets(context.device, writes.len, &writes, 0, null);
}

fn writeCloudSet(
    context: *ctx.VkContext,
    set: vk.VkDescriptorSet,
    ubo_buf: vk.VkBuffer,
    color_buf: vk.VkBuffer,
) void {
    writeSkySet(context, set, ubo_buf, color_buf); // same layout
}

// ---------------------------------------------------------------------------
// Misc
// ---------------------------------------------------------------------------

fn floorDiv(a: i32, b: i32) i32 {
    return @divFloor(a, b);
}

fn linearIdx(x: usize, y: usize, z: usize, xc: usize, yc: usize) usize {
    return (z * yc + y) * xc + x;
}

const BlockId = struct {
    pub const air: u8 = 0;
    pub const rock: u8 = 1;
    pub const grass: u8 = 2;
    pub const dirt: u8 = 3;
    pub const cobblestone: u8 = 4;
    pub const wood: u8 = 5;
    pub const sapling: u8 = 6;
    pub const unbreakable: u8 = 7;
    pub const calm_water: u8 = 8;
    pub const water: u8 = 9;
    pub const lava: u8 = 10;
    pub const sand: u8 = 12;
    pub const gravel: u8 = 13;
    pub const gold_ore: u8 = 14;
    pub const iron_ore: u8 = 15;
    pub const coal_ore: u8 = 16;
    pub const wood_trunk: u8 = 17;
    pub const leaves: u8 = 18;
    pub const sponge: u8 = 19;
    pub const glass: u8 = 20;
    pub const lapis_ore: u8 = 21;
    pub const sandstone: u8 = 24;
    pub const bed: u8 = 26;
    pub const web: u8 = 30;
    pub const tallgrass: u8 = 31;
    pub const deadbush: u8 = 32;
    pub const flower: u8 = 37;
    pub const rose: u8 = 38;
    pub const mushroom1: u8 = 39;
    pub const mushroom2: u8 = 40;
    pub const top_snow: u8 = 78;
    pub const ice: u8 = 79;
    pub const redstone_ore: u8 = 73;
    pub const emerald_ore: u8 = 129;
    pub const cactus: u8 = 81;
    pub const clay: u8 = 82;
    pub const reeds: u8 = 83;
    pub const leaves_spruce: u8 = 200;
};

fn getBlockLayer(id: u8) ?usize {
    if (id == 0) return null;
    if (id == 8 or id == 9) return 2; // water
    if (id == 18 or id == 20 or id == 6 or id == 31 or id == 37 or id == 38 or id == 39 or id == 40 or id == 83 or id == 200) {
        return 1; // leaves, glass, decoration blocks
    }
    return 0; // opaque solid
}

fn isFaceVisible(block_id: u8, neighbor_id: u8) bool {
    if (neighbor_id == 0) return true; // air
    if (isDecor(neighbor_id)) return true;
    const is_liquid = neighbor_id == BlockId.calm_water or neighbor_id == BlockId.water;
    const self_liquid = block_id == BlockId.calm_water or block_id == BlockId.water;
    if (is_liquid) {
        return !self_liquid;
    }
    if (neighbor_id == BlockId.glass or neighbor_id == BlockId.leaves or neighbor_id == BlockId.leaves_spruce) {
        return block_id != neighbor_id;
    }
    return false; // neighbor is solid opaque
}

fn isDecor(id: u8) bool {
    return id == BlockId.sapling or
        id == BlockId.tallgrass or
        id == BlockId.deadbush or
        id == BlockId.flower or
        id == BlockId.rose or
        id == BlockId.mushroom1 or
        id == BlockId.mushroom2 or
        id == BlockId.reeds;
}

fn getBlockColor(block_id: u8, face: enum { up, down, north, south, east, west }) [3]f32 {
    const base_color: [3]f32 = switch (block_id) {
        BlockId.grass => if (face == .up)
            [3]f32{ 0.35, 0.65, 0.25 } // grass top
        else if (face == .down)
            [3]f32{ 0.45, 0.3, 0.15 } // dirt bottom
        else
            [3]f32{ 0.45, 0.35, 0.25 }, // grass side
        BlockId.dirt => [3]f32{ 0.45, 0.3, 0.15 },
        BlockId.rock => [3]f32{ 0.5, 0.5, 0.5 },
        BlockId.cobblestone => [3]f32{ 0.4, 0.4, 0.4 },
        BlockId.wood, BlockId.wood_trunk => [3]f32{ 0.55, 0.4, 0.25 },
        BlockId.leaves, BlockId.leaves_spruce => [3]f32{ 0.15, 0.5, 0.15 },
        BlockId.glass => [3]f32{ 0.9, 0.9, 1.0 },
        BlockId.calm_water, BlockId.water => [3]f32{ 0.2, 0.4, 0.8 },
        BlockId.sand => [3]f32{ 0.85, 0.8, 0.55 },
        BlockId.gravel => [3]f32{ 0.45, 0.45, 0.45 },
        BlockId.gold_ore => [3]f32{ 0.85, 0.75, 0.2 },
        BlockId.iron_ore => [3]f32{ 0.75, 0.55, 0.4 },
        BlockId.coal_ore => [3]f32{ 0.2, 0.2, 0.2 },
        BlockId.redstone_ore => [3]f32{ 0.8, 0.2, 0.2 },
        BlockId.emerald_ore => [3]f32{ 0.1, 0.7, 0.3 },
        BlockId.flower => [3]f32{ 0.9, 0.8, 0.1 },
        BlockId.rose => [3]f32{ 0.8, 0.1, 0.2 },
        BlockId.tallgrass => [3]f32{ 0.3, 0.6, 0.2 },
        else => [3]f32{ 0.7, 0.5, 0.7 }, // debug purple
    };

    const factor: f32 = switch (face) {
        .up => 1.0,
        .north, .south => 0.8,
        .east, .west => 0.6,
        .down => 0.5,
    };

    return [3]f32{ base_color[0] * factor, base_color[1] * factor, base_color[2] * factor };
}

fn getBlockTextureIndex(block_id: u8, face: enum { up, down, north, south, east, west }) u8 {
    return switch (block_id) {
        BlockId.grass => switch (face) {
            .up => 0,
            .down => 2,
            else => 3,
        },
        BlockId.rock => 1,
        BlockId.dirt => 2,
        BlockId.cobblestone => 16,
        BlockId.wood => 4, // Wood planks
        BlockId.wood_trunk => switch (face) {
            .up, .down => 21,
            else => 20,
        },
        BlockId.leaves, BlockId.leaves_spruce => 52,
        BlockId.glass => 49,
        BlockId.calm_water, BlockId.water => 205,
        BlockId.sand => 18,
        BlockId.gravel => 19,
        BlockId.gold_ore => 32,
        BlockId.iron_ore => 33,
        BlockId.coal_ore => 34,
        BlockId.redstone_ore => 51,
        BlockId.emerald_ore => 50,
        BlockId.flower => 13,
        BlockId.rose => 12,
        BlockId.tallgrass => 39,
        BlockId.sapling => 15,
        BlockId.deadbush => 55,
        BlockId.mushroom1 => 29,
        BlockId.mushroom2 => 28,
        BlockId.reeds => 73,
        BlockId.sponge => 48,
        BlockId.lapis_ore => 160,
        BlockId.sandstone => switch (face) {
            .up => 176,
            .down => 208,
            else => 192,
        },
        BlockId.cactus => switch (face) {
            .up, .down => 75,
            else => 76,
        },
        BlockId.clay => 72,
        BlockId.ice => 67,
        BlockId.top_snow => 66,
        BlockId.unbreakable => 17, // Bedrock
        else => 1,
    };
}
