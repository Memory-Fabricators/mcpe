//! Set time packet - syncs world time.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const SetTimePacket = struct {
    time: i32,

    pub fn init(t: i32) SetTimePacket {
        return .{ .time = t };
    }

    pub fn write(self: *const SetTimePacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.time));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !SetTimePacket {
        return .{ .time = @bitCast(try bs.readU32()) };
    }
};
