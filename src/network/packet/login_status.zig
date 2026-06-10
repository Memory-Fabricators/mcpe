//! Login status packet - server response to login.

const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const LoginStatusPacket = struct {
    status: i32,

    pub fn init(status: i32) LoginStatusPacket {
        return .{ .status = status };
    }

    pub fn write(self: *const LoginStatusPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.status));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !LoginStatusPacket {
        return .{ .status = @bitCast(try bs.readU32()) };
    }
};

const std = @import("std");
