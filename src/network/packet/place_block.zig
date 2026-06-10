//! Place block packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const PlaceBlockPacket = struct {
    entity_id: i32,
    x: i32,
    y: i32,
    z: i32,
    face: u8,
    block_id: u16,
    block_data: u8,

    pub fn write(self: *const PlaceBlockPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU8(self.face);
        try bs.writeU16(self.block_id);
        try bs.writeU8(self.block_data);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !PlaceBlockPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
            .face = try bs.readU8(),
            .block_id = try bs.readU16(),
            .block_data = try bs.readU8(),
        };
    }
};
