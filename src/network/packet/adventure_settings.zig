//! Adventure settings packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const AdventureSettingsPacket = struct {
    flags: i32,

    pub fn init(flags: i32) AdventureSettingsPacket {
        return .{ .flags = flags };
    }

    pub fn write(self: *const AdventureSettingsPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.flags));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !AdventureSettingsPacket {
        return .{ .flags = @bitCast(try bs.readU32()) };
    }
};
