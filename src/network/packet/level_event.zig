//! Level event packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const LevelEventPacket = struct {
    event_id: i16,
    x: i16,
    y: i16,
    z: i16,
    data: i32,

    pub fn write(self: *const LevelEventPacket, bs: *BitStream) !void {
        try bs.writeU16(@bitCast(self.event_id));
        try bs.writeU16(@bitCast(self.x));
        try bs.writeU16(@bitCast(self.y));
        try bs.writeU16(@bitCast(self.z));
        try bs.writeU32(@bitCast(self.data));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !LevelEventPacket {
        return .{
            .event_id = @bitCast(try bs.readU16()),
            .x = @bitCast(try bs.readU16()),
            .y = @bitCast(try bs.readU16()),
            .z = @bitCast(try bs.readU16()),
            .data = @bitCast(try bs.readU32()),
        };
    }
};
