//! Chunk data packet - compressed chunk data.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ChunkDataPacket = struct {
    x: i32,
    z: i32,
    /// Raw chunk data (serialized then read back as opaque blob)
    chunk_data: []u8,

    pub fn write(self: *const ChunkDataPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU16(@intCast(self.chunk_data.len));
        if (self.chunk_data.len > 0) try bs.writeAlignedBytes(self.chunk_data);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !ChunkDataPacket {
        const x: i32 = @bitCast(try bs.readU32());
        const z: i32 = @bitCast(try bs.readU32());
        const len = try bs.readU16();
        const data = if (len > 0) try bs.readBytesAlloc(allocator) else &.{};
        return .{ .x = x, .z = z, .chunk_data = data };
    }

    pub fn deinit(self: *ChunkDataPacket, allocator: std.mem.Allocator) void {
        if (self.chunk_data.len > 0) allocator.free(self.chunk_data);
    }
};
