//! Set entity motion packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const SetEntityMotionPacket = struct {
    entity_id: i32,
    xd: i16,
    yd: i16,
    zd: i16,

    pub fn write(self: *const SetEntityMotionPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU16(@bitCast(self.xd));
        try bs.writeU16(@bitCast(self.yd));
        try bs.writeU16(@bitCast(self.zd));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !SetEntityMotionPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .xd = @bitCast(try bs.readU16()),
            .yd = @bitCast(try bs.readU16()),
            .zd = @bitCast(try bs.readU16()),
        };
    }
};
