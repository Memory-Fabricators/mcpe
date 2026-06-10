//! Perlin noise - multi-octave noise generator.
//! Ported from world/level/levelgen/synth/PerlinNoise.h/.cpp
//!
//! Stacks multiple ImprovedNoise octaves for richer terrain generation.

const std = @import("std");
const ImprovedNoise = @import("improved_noise.zig").ImprovedNoise;
const Random = @import("random").Random;

pub const PerlinNoise = struct {
    levels: []ImprovedNoise,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, random: *Random, num_levels: u32) !PerlinNoise {
        const levels = try allocator.alloc(ImprovedNoise, num_levels);
        errdefer allocator.free(levels);
        for (0..num_levels) |i| {
            levels[i] = ImprovedNoise.init(random);
        }
        return .{ .levels = levels, .allocator = allocator };
    }

    pub fn deinit(self: *PerlinNoise) void {
        self.allocator.free(self.levels);
        self.* = undefined;
    }

    pub fn getValue(self: *const PerlinNoise, x: f32, y: f32) f32 {
        var value: f32 = 0;
        var pow: f32 = 1;
        for (self.levels) |*level| {
            value += level.getValue(x * pow, y * pow) / pow;
            pow /= 2;
        }
        return value;
    }

    pub fn getValue3D(self: *const PerlinNoise, x: f32, y: f32, z: f32) f32 {
        var value: f32 = 0;
        var pow: f32 = 1;
        for (self.levels) |*level| {
            value += level.getValue3D(x * pow, y * pow, z * pow) / pow;
            pow /= 2;
        }
        return value;
    }

    /// Generate a 3D region of noise into buffer.
    /// If buffer is null, allocates and returns a new buffer.
    pub fn getRegion(
        self: *const PerlinNoise,
        buffer: ?[]f32,
        x: f32,
        y: f32,
        z: f32,
        x_size: i32,
        y_size: i32,
        z_size: i32,
        x_scale: f32,
        y_scale: f32,
        z_scale: f32,
    ) ![]f32 {
        const size: usize = @intCast(x_size * y_size * z_size);

        const buf: []f32 = if (buffer) |b| b else blk: {
            break :blk try self.allocator.alloc(f32, size);
        };
        @memset(buf, 0);

        var pow: f32 = 1;
        for (self.levels) |*level| {
            level.add(buf, x, y, z, x_size, y_size, z_size, x_scale * pow, y_scale * pow, z_scale * pow, pow);
            pow /= 2;
        }

        return buf;
    }

    /// 2D convenience overload
    pub fn getRegion2D(
        self: *const PerlinNoise,
        buffer: ?[]f32,
        x: i32,
        z: i32,
        x_size: i32,
        z_size: i32,
        x_scale: f32,
        z_scale: f32,
        pow: f32,
    ) ![]f32 {
        _ = pow;
        return self.getRegion(buffer, @floatFromInt(x), 10.0, @floatFromInt(z), x_size, 1, z_size, x_scale, 1, z_scale);
    }
};
