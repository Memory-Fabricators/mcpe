//! Add item entity packet - dropped item entity.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const AddItemEntityPacket = struct {
    entity_id: i32,
    item_id: i16,
    item_aux: i16,
    x: f32,
    y: f32,
    z: f32,
    y_rot: i8,
    x_rot: i8,
    roll: i8,
    pitch: i8,

    pub fn write(self: *const AddItemEntityPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU16(@bitCast(self.item_id));
        try bs.writeU16(@bitCast(self.item_aux));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
        try bs.writeU8(@bitCast(self.y_rot));
        try bs.writeU8(@bitCast(self.x_rot));
        try bs.writeU8(@bitCast(self.roll));
        try bs.writeU8(@bitCast(self.pitch));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !AddItemEntityPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .item_id = @bitCast(try bs.readU16()),
            .item_aux = @bitCast(try bs.readU16()),
            .x = try bs.readF32(),
            .y = try bs.readF32(),
            .z = try bs.readF32(),
            .y_rot = @bitCast(try bs.readU8()),
            .x_rot = @bitCast(try bs.readU8()),
            .roll = @bitCast(try bs.readU8()),
            .pitch = @bitCast(try bs.readU8()),
        };
    }
};
