//! Request chunk packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const RequestChunkPacket = struct {
    x: i32,
    z: i32,

    pub fn init(x: i32, z: i32) RequestChunkPacket {
        return .{ .x = x, .z = z };
    }

    pub fn write(self: *const RequestChunkPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.z));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !RequestChunkPacket {
        return .{
            .x = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
        };
    }
};
