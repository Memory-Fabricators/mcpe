//! Random level source - generates infinite Minecraft terrain.
//! Ported from world/level/levelgen/RandomLevelSource.h/.cpp
//!
//! Uses multiple PerlinNoise octaves to generate heightmaps,
//! then applies biome surfaces, ore veins, trees, and features.

const std = @import("std");
const Random = @import("random").Random;
const PerlinNoise = @import("synth/perlin_noise.zig").PerlinNoise;
const chunk = @import("chunk.zig");

const ChunkPos = chunk.ChunkPos;
const DataLayer = chunk.DataLayer;
const level_height = chunk.level_height;
const chunk_width = chunk.chunk_width;
const chunk_depth = chunk.chunk_depth;
const chunk_columns = chunk.chunk_columns;
const chunk_block_count = chunk.chunk_block_count;

const CHUNK_HEIGHT: i32 = 8;
const CHUNK_WIDTH: i32 = 4;
const MAX_BUFFER_SIZE: usize = 1024;

// ---------------------------------------------------------------------------
// Block IDs (subset used by generator)
// ---------------------------------------------------------------------------

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

/// Ore feature - places blobs of ore
const OreFeature = struct {
    block_id: u8,
    cluster_size: i32,

    pub fn place(self: OreFeature, blocks: []u8, rng: *Random, x: i32, y: i32, z: i32, world_height: i32) void {
        const f = @as(f32, @floatFromInt(rng.nextIntBounded(256))) / 256.0;
        const radius_count = @as(f32, @floatFromInt(self.cluster_size)) * (0.5 + f * 2.0);
        var radius_angle = @as(f32, @floatFromInt(rng.nextIntBounded(256))) / 256.0 * std.math.pi * 2.0;
        const radius_y_angle = @as(f32, @floatFromInt(rng.nextIntBounded(256))) / 256.0 * std.math.pi;

        const origin_x: f32 = @floatFromInt(x);
        const origin_y: f32 = @floatFromInt(y);
        const origin_z: f32 = @floatFromInt(z);

        var placed: i32 = 0;
        while (placed < self.cluster_size) : (placed += 1) {
            const dist = radius_count * (std.math.sin(radius_angle) * std.math.cos(radius_y_angle));
            const dx = std.math.sin(radius_angle) * std.math.sin(radius_y_angle);
            const dy = std.math.cos(radius_angle);
            const dz = std.math.cos(radius_angle) * std.math.sin(radius_y_angle);

            const bx: i32 = @intFromFloat(origin_x + dist * dx);
            const by: i32 = @intFromFloat(origin_y + dist * dy);
            const bz: i32 = @intFromFloat(origin_z + dist * dz);

            if (bx < 0 or bx >= chunk_width or by < 0 or by >= world_height or bz < 0 or bz >= chunk_depth) continue;

            const off = chunk.blockOffset(bx, by, bz);
            if (blocks[off] == BlockId.rock) {
                blocks[off] = self.block_id;
            }

            radius_angle += @as(f32, @floatFromInt(rng.nextIntBounded(256))) / 256.0 * 0.2;
            radius_y_angle += @as(f32, @floatFromInt(rng.nextIntBounded(256))) / 256.0 * 0.2;
        }
    }
};

// ---------------------------------------------------------------------------
// RandomLevelSource
// ---------------------------------------------------------------------------

pub const RandomLevelSource = struct {
    allocator: std.mem.Allocator,
    random: Random,
    seed: i64,

    lperlin_noise1: PerlinNoise,
    lperlin_noise2: PerlinNoise,
    perlin_noise1: PerlinNoise,
    perlin_noise2: PerlinNoise,
    perlin_noise3: PerlinNoise,
    scale_noise: PerlinNoise,
    depth_noise: PerlinNoise,
    forest_noise: PerlinNoise,

    chunk_map: std.AutoHashMap(i64, LevelChunk),

    // Working buffers
    buffer: []f32,
    sand_buffer: [16 * 16]f32,
    gravel_buffer: [16 * 16]f32,
    depth_buffer: [16 * 16]f32,

    pub fn init(allocator: std.mem.Allocator, seed: i64) !RandomLevelSource {
        var random = Random.init(seed);

        // All PerlinNoise instances with the same random, different octave counts
        var perlin1 = try PerlinNoise.init(allocator, &random, 16);
        errdefer perlin1.deinit();
        var perlin2 = try PerlinNoise.init(allocator, &random, 16);
        errdefer perlin2.deinit();
        var pn1 = try PerlinNoise.init(allocator, &random, 8);
        errdefer pn1.deinit();
        var pn2 = try PerlinNoise.init(allocator, &random, 4);
        errdefer pn2.deinit();
        var pn3 = try PerlinNoise.init(allocator, &random, 4);
        errdefer pn3.deinit();
        var sn = try PerlinNoise.init(allocator, &random, 10);
        errdefer sn.deinit();
        var dn = try PerlinNoise.init(allocator, &random, 16);
        errdefer dn.deinit();
        var fn_noise = try PerlinNoise.init(allocator, &random, 8);
        errdefer fn_noise.deinit();

        const buf = try allocator.alloc(f32, MAX_BUFFER_SIZE);
        @memset(buf, 0);

        return .{
            .allocator = allocator,
            .random = random,
            .seed = seed,
            .lperlin_noise1 = perlin1,
            .lperlin_noise2 = perlin2,
            .perlin_noise1 = pn1,
            .perlin_noise2 = pn2,
            .perlin_noise3 = pn3,
            .scale_noise = sn,
            .depth_noise = dn,
            .forest_noise = fn_noise,
            .chunk_map = std.AutoHashMap(i64, LevelChunk).init(allocator),
            .buffer = buf,
            .sand_buffer = @splat(0),
            .gravel_buffer = @splat(0),
            .depth_buffer = @splat(0),
        };
    }

    pub fn deinit(self: *RandomLevelSource) void {
        var it = self.chunk_map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.chunk_map.deinit();

        self.lperlin_noise1.deinit();
        self.lperlin_noise2.deinit();
        self.perlin_noise1.deinit();
        self.perlin_noise2.deinit();
        self.perlin_noise3.deinit();
        self.scale_noise.deinit();
        self.depth_noise.deinit();
        self.forest_noise.deinit();
        self.allocator.free(self.buffer);
        self.* = undefined;
    }

    /// Get or generate a chunk at coordinates
    pub fn getChunk(self: *RandomLevelSource, x_offs: i32, z_offs: i32) !*LevelChunk {
        const hash = ChunkPos.hashCode(x_offs, z_offs);
        if (self.chunk_map.getPtr(hash)) |existing| return existing;

        // Seed for this chunk position
        const chunk_seed: i64 = @as(i64, x_offs) * 341872712 + @as(i64, z_offs) * 132899541;
        self.random.setSeed(chunk_seed);

        const blocks = try self.allocator.alloc(u8, @intCast(chunk_block_count));
        errdefer self.allocator.free(blocks);

        // Generate terrain
        try self.generateTerrain(x_offs, z_offs, blocks);

        // Build the chunk
        const level_chunk = try LevelChunk.init(self.allocator, blocks, x_offs, z_offs);
        try self.chunk_map.put(hash, level_chunk);
        return self.chunk_map.getPtr(hash).?;
    }

    /// Generate terrain blocks for a chunk
    fn generateTerrain(self: *RandomLevelSource, x_offs: i32, z_offs: i32, blocks: []u8) !void {
        const water_height: i32 = level_height - 64;

        const x_chunks: i32 = 16 / CHUNK_WIDTH;
        const z_chunks: i32 = 16 / CHUNK_WIDTH;
        const y_size: i32 = 128 / CHUNK_HEIGHT + 1;
        const x_size: i32 = x_chunks + 1;
        const z_size: i32 = z_chunks + 1;

        // Generate 3D noise heights
        const heights = try self.getHeights(
            self.buffer,
            x_offs * x_chunks,
            0,
            z_offs * z_chunks,
            x_size,
            y_size,
            z_size,
        );

        // Prepare heights - interpolate noise into block data
        var xc: i32 = 0;
        while (xc < x_chunks) : (xc += 1) {
            var zc: i32 = 0;
            while (zc < z_chunks) : (zc += 1) {
                var yc: i32 = 0;
                while (yc < 128 / CHUNK_HEIGHT) : (yc += 1) {
                    const s0 = heights[@as(usize, @intCast((xc + 0) * z_size + (zc + 0))) * @as(usize, @intCast(y_size)) + @as(usize, @intCast(yc + 0))];
                    const s1 = heights[@as(usize, @intCast((xc + 0) * z_size + (zc + 1))) * @as(usize, @intCast(y_size)) + @as(usize, @intCast(yc + 0))];
                    const s2 = heights[@as(usize, @intCast((xc + 1) * z_size + (zc + 0))) * @as(usize, @intCast(y_size)) + @as(usize, @intCast(yc + 0))];
                    const s3 = heights[@as(usize, @intCast((xc + 1) * z_size + (zc + 1))) * @as(usize, @intCast(y_size)) + @as(usize, @intCast(yc + 0))];

                    var y: i32 = 0;
                    while (y < CHUNK_HEIGHT) : (y += 1) {
                        const x_step: f32 = 1.0 / @as(f32, @floatFromInt(CHUNK_WIDTH));

                        var _s0 = s0;
                        var _s1 = s1;
                        const _s0a = (s2 - s0) * x_step;
                        const _s1a = (s3 - s1) * x_step;

                        var x: i32 = 0;
                        while (x < CHUNK_WIDTH) : (x += 1) {
                            var offs: usize = @intCast(
                                (@as(u32, @bitCast(x + xc * CHUNK_WIDTH)) << 11) |
                                    (@as(u32, @bitCast(zc * CHUNK_WIDTH)) << 7) |
                                    @as(u32, @bitCast(yc * CHUNK_HEIGHT + y)),
                            );
                            const step: usize = 1 << 7;
                            const z_step: f32 = 1.0 / @as(f32, @floatFromInt(CHUNK_WIDTH));

                            var val = _s0;
                            const vala = (_s1 - _s0) * z_step;

                            var z: i32 = 0;
                            while (z < CHUNK_WIDTH) : (z += 1) {
                                var tile_id: u8 = BlockId.air;

                                if (yc * CHUNK_HEIGHT + y < water_height) {
                                    tile_id = BlockId.calm_water;
                                }
                                if (val > 0) {
                                    tile_id = BlockId.rock;
                                }

                                blocks[offs] = tile_id;
                                offs += step;
                                val += vala;
                            }
                            _s0 += _s0a;
                            _s1 += _s1a;
                        }
                        // Interpolate along y
                    }
                }
            }
        }

        // Build surfaces
        try self.buildSurfaces(x_offs, z_offs, blocks);

        // Post-process: ores, features
        self.postProcess(x_offs, z_offs, blocks);
    }

    /// Generate the 3D height noise field
    fn getHeights(
        self: *RandomLevelSource,
        buf: []f32,
        x: i32,
        y: i32,
        z: i32,
        x_size: i32,
        y_size: i32,
        z_size: i32,
    ) ![]f32 {
        const s: f32 = 684.412;
        const hs: f32 = 684.412;

        // Scale and depth noise are 2D
        const w = x_size * z_size;
        _ = try self.scale_noise.getRegion(
            null,
            @floatFromInt(x),
            10.0,
            @floatFromInt(z),
            x_size,
            1,
            z_size,
            1.121,
            1.0,
            1.121,
        );
        _ = try self.depth_noise.getRegion(
            null,
            @floatFromInt(x),
            10.0,
            @floatFromInt(z),
            x_size,
            1,
            z_size,
            200.0,
            1.0,
            200.0,
        );

        // 3D noise layers
        const pnr = try self.perlin_noise1.getRegion(null, @floatFromInt(x), @floatFromInt(y), @floatFromInt(z), x_size, y_size, z_size, s / 80.0, hs / 160.0, s / 80.0);
        const ar = try self.lperlin_noise1.getRegion(null, @floatFromInt(x), @floatFromInt(y), @floatFromInt(z), x_size, y_size, z_size, s, hs, s);
        const br = try self.lperlin_noise2.getRegion(null, @floatFromInt(x), @floatFromInt(y), @floatFromInt(z), x_size, y_size, z_size, s, hs, s);

        _ = w;
        defer self.allocator.free(pnr);
        defer self.allocator.free(ar);
        defer self.allocator.free(br);

        // Combine noise layers into final heights
        var p: usize = 0;

        var xx: i32 = 0;
        while (xx < x_size) : (xx += 1) {
            var zz: i32 = 0;
            while (zz < z_size) : (zz += 1) {
                const y_center = @as(f32, @floatFromInt(y_size)) / 2.0;

                var yy: i32 = 0;
                while (yy < y_size) : (yy += 1) {
                    var val: f32 = 0;

                    const y_offs = (@as(f32, @floatFromInt(yy)) - y_center) * 12.0;
                    const scaled_y_offs = if (y_offs < 0) y_offs * 4.0 else y_offs;

                    const bb = ar[p] / 512.0;
                    const cc = br[p] / 512.0;

                    const v = (pnr[p] / 10.0 + 1.0) / 2.0;
                    if (v < 0) {
                        val = bb;
                    } else if (v > 1) {
                        val = cc;
                    } else {
                        val = bb + (cc - bb) * v;
                    }
                    val -= scaled_y_offs;

                    // Slide off at top
                    if (yy > y_size - 4) {
                        const slide = @as(f32, @floatFromInt(yy - (y_size - 4))) / 3.0;
                        val = val * (1.0 - slide) + (-10.0) * slide;
                    }

                    buf[p] = val;
                    p += 1;
                }
            }
        }

        return buf[0..@intCast(x_size * y_size * z_size)];
    }

    /// Build biome surfaces (grass, dirt, sand, gravel)
    fn buildSurfaces(self: *RandomLevelSource, x_offs: i32, z_offs: i32, blocks: []u8) !void {
        const water_height = level_height - 64;

        // Generate surface noise layers
        const s: f32 = 1.0 / 32.0;
        _ = try self.perlin_noise2.getRegion(&self.sand_buffer, @floatFromInt(x_offs * 16), 10.0, @floatFromInt(z_offs * 16), 16, 1, 16, s, 1.0, s);
        _ = try self.perlin_noise2.getRegion(&self.gravel_buffer, @floatFromInt(x_offs * 16), 109.01340, @floatFromInt(z_offs * 16), 16, 1, 16, s, 1.0, s);
        _ = try self.perlin_noise3.getRegion(&self.depth_buffer, @floatFromInt(x_offs * 16), 10.0, @floatFromInt(z_offs * 16), 16, 1, 16, s * 2.0, 1.0, s * 2.0);

        var x: i32 = 0;
        while (x < 16) : (x += 1) {
            var z: i32 = 0;
            while (z < 16) : (z += 1) {
                const sand_flag = (self.sand_buffer[@intCast(x + z * 16)] + self.random.nextFloat() * 0.2) > 0;
                const gravel_flag = (self.gravel_buffer[@intCast(x + z * 16)] + self.random.nextFloat() * 0.2) > 3;
                const run_depth: i32 = @intFromFloat(self.depth_buffer[@intCast(x + z * 16)] / 3.0 + 3.0 + self.random.nextFloat() * 0.25);

                var run: i32 = -1;

                var top: u8 = BlockId.grass;
                var material: u8 = BlockId.dirt;

                var y: i32 = 127;
                while (y >= 0) : (y -= 1) {
                    const offs = blockOffset(z, y, x);

                    if (y <= self.random.nextIntBounded(5)) {
                        blocks[offs] = BlockId.unbreakable;
                    } else {
                        const old = blocks[offs];

                        if (old == BlockId.air) {
                            run = -1;
                        } else if (old == BlockId.rock) {
                            if (run == -1) {
                                if (run_depth <= 0) {
                                    top = 0;
                                    material = BlockId.rock;
                                } else if (y >= water_height - 4 and y <= water_height + 1) {
                                    top = BlockId.grass;
                                    material = BlockId.dirt;

                                    if (gravel_flag) {
                                        top = 0;
                                        material = BlockId.gravel;
                                    }
                                    if (sand_flag) {
                                        top = BlockId.sand;
                                        material = BlockId.sand;
                                    }
                                }

                                if (y < water_height and top == 0) {
                                    top = BlockId.calm_water;
                                }

                                run = run_depth;
                                if (y >= water_height - 1) {
                                    blocks[offs] = top;
                                } else {
                                    blocks[offs] = material;
                                }
                            } else if (run > 0) {
                                run -= 1;
                                blocks[offs] = material;

                                // Sandstone under sand
                                if (run == 0 and material == BlockId.sand) {
                                    run = self.random.nextIntBounded(4);
                                    material = BlockId.sandstone;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Post-process: place ore veins, trees, features
    fn postProcess(self: *RandomLevelSource, x_offs: i32, z_offs: i32, blocks: []u8) void {
        const xo = x_offs * 16;
        const zo = z_offs * 16;

        self.random.setSeed(self.seed);
        const x_scale: i32 = self.random.nextInt() / 2 * 2 + 1;
        const z_scale: i32 = self.random.nextInt() / 2 * 2 + 1;
        self.random.setSeed((@as(i64, x_offs) * @as(i64, x_scale) + @as(i64, z_offs) * @as(i64, z_scale)) ^ self.seed);

        // Clay veins
        var i: i32 = 0;
        while (i < 10) : (i += 1) {
            const cx = self.random.nextIntBounded(16);
            const cy = self.random.nextIntBounded(128);
            const cz = self.random.nextIntBounded(16);
            const feature = OreFeature{ .block_id = BlockId.clay, .cluster_size = 32 };
            feature.place(blocks, &self.random, cx, cy, cz, level_height);
        }

        // Dirt veins
        i = 0;
        while (i < 20) : (i += 1) {
            const dx = self.random.nextIntBounded(16);
            const dy = self.random.nextIntBounded(128);
            const dz = self.random.nextIntBounded(16);
            const f1 = OreFeature{ .block_id = BlockId.dirt, .cluster_size = 32 };
            f1.place(blocks, &self.random, dx, dy, dz, level_height);
        }

        // Gravel veins
        i = 0;
        while (i < 10) : (i += 1) {
            const gx = self.random.nextIntBounded(16);
            const gy = self.random.nextIntBounded(128);
            const gz = self.random.nextIntBounded(16);
            const f2 = OreFeature{ .block_id = BlockId.gravel, .cluster_size = 32 };
            f2.place(blocks, &self.random, gx, gy, gz, level_height);
        }

        // Coal ore
        i = 0;
        while (i < 20) : (i += 1) {
            const ox = self.random.nextIntBounded(16);
            const oy = self.random.nextIntBounded(128);
            const oz = self.random.nextIntBounded(16);
            const f3 = OreFeature{ .block_id = BlockId.coal_ore, .cluster_size = 16 };
            f3.place(blocks, &self.random, ox, oy, oz, level_height);
        }

        // Iron ore
        i = 0;
        while (i < 20) : (i += 1) {
            const ox = self.random.nextIntBounded(16);
            const oy = self.random.nextIntBounded(64);
            const oz = self.random.nextIntBounded(16);
            const f4 = OreFeature{ .block_id = BlockId.iron_ore, .cluster_size = 8 };
            f4.place(blocks, &self.random, ox, oy, oz, level_height);
        }

        // Gold ore
        i = 0;
        while (i < 2) : (i += 1) {
            const ox = self.random.nextIntBounded(16);
            const oy = self.random.nextIntBounded(32);
            const oz = self.random.nextIntBounded(16);
            const f5 = OreFeature{ .block_id = BlockId.gold_ore, .cluster_size = 8 };
            f5.place(blocks, &self.random, ox, oy, oz, level_height);
        }

        // Redstone ore
        i = 0;
        while (i < 8) : (i += 1) {
            const ox = self.random.nextIntBounded(16);
            const oy = self.random.nextIntBounded(16);
            const oz = self.random.nextIntBounded(16);
            const f6 = OreFeature{ .block_id = BlockId.redstone_ore, .cluster_size = 7 };
            f6.place(blocks, &self.random, ox, oy, oz, level_height);
        }

        // Emerald ore
        i = 0;
        while (i < 1) : (i += 1) {
            const ox = self.random.nextIntBounded(16);
            const oy = self.random.nextIntBounded(16);
            const oz = self.random.nextIntBounded(16);
            const f7 = OreFeature{ .block_id = BlockId.emerald_ore, .cluster_size = 7 };
            f7.place(blocks, &self.random, ox, oy, oz, level_height);
        }

        // Lapis ore
        i = 0;
        while (i < 1) : (i += 1) {
            const ox = self.random.nextIntBounded(16);
            const oy: i32 = self.random.nextIntBounded(16) + self.random.nextIntBounded(16);
            const oz = self.random.nextIntBounded(16);
            const f8 = OreFeature{ .block_id = BlockId.lapis_ore, .cluster_size = 6 };
            f8.place(blocks, &self.random, ox, oy, oz, level_height);
        }

        _ = xo;
        _ = zo;
    }

    /// Recalculate the heightmap for a chunk
    pub fn recalcHeightmap(blocks: []const u8, heightmap: []i8) void {
        var x: i32 = 0;
        while (x < 16) : (x += 1) {
            var z: i32 = 0;
            while (z < 16) : (z += 1) {
                var y: i32 = 127;
                while (y >= 0) : (y -= 1) {
                    const idx = blockOffset(x, y, z);
                    if (blocks[idx] != BlockId.air) {
                        heightmap[@intCast(x + z * 16)] = @intCast(y);
                        break;
                    }
                }
            }
        }
    }
};

/// A chunk of the world - holds block data
pub const LevelChunk = struct {
    blocks: []u8,
    heightmap: [256]i8,
    x: i32,
    z: i32,

    pub fn init(allocator: std.mem.Allocator, blocks: []u8, x: i32, z: i32) !LevelChunk {
        _ = allocator;
        var hmap: [256]i8 = @splat(0);
        RandomLevelSource.recalcHeightmap(blocks, &hmap);
        return .{
            .blocks = blocks,
            .heightmap = hmap,
            .x = x,
            .z = z,
        };
    }

    pub fn deinit(self: *LevelChunk, allocator: std.mem.Allocator) void {
        allocator.free(self.blocks);
        self.* = undefined;
    }
};

// Helper for blockOffset in surface code
fn blockOffset(x: i32, y: i32, z: i32) usize {
    return chunk.blockOffset(x, y, z);
}
