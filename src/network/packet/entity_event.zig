//! Entity event packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const EntityEventPacket = struct {
    entity_id: i32,
    event: u8,

    pub fn write(self: *const EntityEventPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU8(self.event);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !EntityEventPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .event = try bs.readU8(),
        };
    }
};
