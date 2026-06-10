//! Use item packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const UseItemPacket = struct {
    x: i32,
    y: i32,
    z: i32,
    face: i32,
    item_id: u16,
    item_data: u8,

    pub fn write(self: *const UseItemPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU32(@bitCast(self.face));
        try bs.writeU16(self.item_id);
        try bs.writeU8(self.item_data);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !UseItemPacket {
        return .{
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
            .face = @bitCast(try bs.readU32()),
            .item_id = try bs.readU16(),
            .item_data = try bs.readU8(),
        };
    }
};
