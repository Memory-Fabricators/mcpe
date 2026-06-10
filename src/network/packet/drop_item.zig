//! Drop item packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;
const pkt = @import("../packet.zig");

pub const DropItemPacket = struct {
    entity_id: i32,
    item: pkt.ItemInstance,

    pub fn write(self: *const DropItemPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try self.item.write(bs);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !DropItemPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .item = try pkt.ItemInstance.read(bs),
        };
    }
};
