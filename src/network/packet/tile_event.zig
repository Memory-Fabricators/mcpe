//! Tile event packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const TileEventPacket = struct {
    x: i32,
    y: i32,
    z: i32,
    case_1: i32,
    case_2: i32,

    pub fn write(self: *const TileEventPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU32(@bitCast(self.case_1));
        try bs.writeU32(@bitCast(self.case_2));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !TileEventPacket {
        return .{
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
            .case_1 = @bitCast(try bs.readU32()),
            .case_2 = @bitCast(try bs.readU32()),
        };
    }
};
