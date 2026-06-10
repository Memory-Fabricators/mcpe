//! Remove block packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const RemoveBlockPacket = struct {
    entity_id: i32,
    x: i32,
    y: i32,
    z: i32,

    pub fn init(eid: i32, x: i32, y: i32, z: i32) RemoveBlockPacket {
        return .{ .entity_id = eid, .x = x, .y = y, .z = z };
    }

    pub fn write(self: *const RemoveBlockPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !RemoveBlockPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
        };
    }
};
