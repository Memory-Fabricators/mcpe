//! Container set slot packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;
const pkt = @import("../packet.zig");

pub const ContainerSetSlotPacket = struct {
    window_id: u8,
    slot: i16,
    item: pkt.ItemInstance,

    pub fn write(self: *const ContainerSetSlotPacket, bs: *BitStream) !void {
        try bs.writeU8(self.window_id);
        try bs.writeU16(@bitCast(self.slot));
        try self.item.write(bs);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !ContainerSetSlotPacket {
        return .{
            .window_id = try bs.readU8(),
            .slot = @bitCast(try bs.readU16()),
            .item = try pkt.ItemInstance.read(bs),
        };
    }
};
