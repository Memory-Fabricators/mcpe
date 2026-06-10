//! Set spawn position packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const SetSpawnPositionPacket = struct {
    x: i32,
    y: i32,
    z: i32,

    pub fn init(x: i32, y: i32, z: i32) SetSpawnPositionPacket {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn write(self: *const SetSpawnPositionPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !SetSpawnPositionPacket {
        return .{
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
        };
    }
};
