//! Set health packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const SetHealthPacket = struct {
    health: i32,

    pub fn init(h: i32) SetHealthPacket {
        return .{ .health = h };
    }

    pub fn write(self: *const SetHealthPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.health));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !SetHealthPacket {
        return .{ .health = @bitCast(try bs.readU32()) };
    }
};
