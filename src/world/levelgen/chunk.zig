//! World level constants and chunk utilities.
//! Ported from LevelConstants.h, ChunkPos.h, DataLayer.h

const std = @import("std");

pub const level_height: i32 = 128;
pub const chunk_width: i32 = 16;
pub const chunk_depth: i32 = 16;
pub const chunk_columns: i32 = chunk_width * chunk_depth;
pub const chunk_block_count: i32 = chunk_columns * level_height;

pub const ChunkPos = struct {
    x: i32,
    z: i32,

    pub fn hashCode(x: i32, z: i32) i64 {
        const ux = @as(u32, @bitCast(x));
        const uz = @as(u32, @bitCast(z));
        const combined = (@as(u64, ux) << 32) | @as(u64, uz);
        return @bitCast(combined);
    }

    pub fn toHash(self: ChunkPos) i64 {
        return hashCode(self.x, self.z);
    }
};

pub const DataLayer = struct {
    data: []u8,
    len: usize,

    pub fn init(allocator: std.mem.Allocator, length: usize) !DataLayer {
        const data_len = length >> 1;
        const data = try allocator.alloc(u8, data_len);
        @memset(data, 0);
        return .{ .data = data, .len = data_len };
    }

    pub fn deinit(self: *DataLayer, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }

    pub fn get(self: *const DataLayer, pos: usize) u8 {
        const slot = pos >> 1;
        const part = pos & 1;
        if (part == 0) {
            return self.data[slot] & 0xf;
        } else {
            return (self.data[slot] >> 4) & 0xf;
        }
    }

    pub fn set(self: *DataLayer, pos: usize, val: u8) void {
        const slot = pos >> 1;
        const part = pos & 1;
        if (part == 0) {
            self.data[slot] = (self.data[slot] & 0xf0) | (val & 0xf);
        } else {
            self.data[slot] = (self.data[slot] & 0x0f) | ((val & 0xf) << 4);
        }
    }

    pub fn setAll(self: *DataLayer, val: u8) void {
        const v = val | (val << 4);
        @memset(self.data, v);
    }
};

pub fn blockOffset(x: i32, y: i32, z: i32) usize {
    const ux: u32 = @bitCast(x);
    const uy: u32 = @bitCast(y);
    const uz: u32 = @bitCast(z);
    return @intCast((ux << 11) | (uz << 7) | uy);
}

pub fn isBlockingLight(id: u8) bool {
    return switch (id) {
        0, 8, 9, 20, 18, 6, 31, 32, 37, 38, 39, 40, 83, 200, 30, 78 => false,
        else => true,
    };
}
