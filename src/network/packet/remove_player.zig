//! Remove player packet - removes a player entity.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const RemovePlayerPacket = struct {
    entity_id: i32,

    pub fn init(id: i32) RemovePlayerPacket {
        return .{ .entity_id = id };
    }

    pub fn write(self: *const RemovePlayerPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !RemovePlayerPacket {
        return .{ .entity_id = @bitCast(try bs.readU32()) };
    }
};
