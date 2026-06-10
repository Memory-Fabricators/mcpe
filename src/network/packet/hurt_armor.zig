//! Hurt armor packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const HurtArmorPacket = struct {
    health: i32,

    pub fn init(health: i32) HurtArmorPacket {
        return .{ .health = health };
    }

    pub fn write(self: *const HurtArmorPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.health));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !HurtArmorPacket {
        return .{ .health = @bitCast(try bs.readU32()) };
    }
};
