//! Player equipment packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const PlayerEquipmentPacket = struct {
    entity_id: i32,
    item_id: u16,
    item_aux_value: u16,

    pub fn init(eid: i32, item: u16, aux: u16) PlayerEquipmentPacket {
        return .{ .entity_id = eid, .item_id = item, .item_aux_value = aux };
    }

    pub fn write(self: *const PlayerEquipmentPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU16(self.item_id);
        try bs.writeU16(self.item_aux_value);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !PlayerEquipmentPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .item_id = try bs.readU16(),
            .item_aux_value = try bs.readU16(),
        };
    }
};
