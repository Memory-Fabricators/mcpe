//! Player armor equipment packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const PlayerArmorEquipmentPacket = struct {
    entity_id: i32,
    helmet: u16,
    chestplate: u16,
    leggings: u16,
    boots: u16,

    pub fn write(self: *const PlayerArmorEquipmentPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU16(self.helmet);
        try bs.writeU16(self.chestplate);
        try bs.writeU16(self.leggings);
        try bs.writeU16(self.boots);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !PlayerArmorEquipmentPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .helmet = try bs.readU16(),
            .chestplate = try bs.readU16(),
            .leggings = try bs.readU16(),
            .boots = try bs.readU16(),
        };
    }
};
