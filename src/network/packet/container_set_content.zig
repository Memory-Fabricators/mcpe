//! Container set content packet - full inventory contents.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;
const pkt = @import("../packet.zig");

pub const ContainerSetContentPacket = struct {
    window_id: u8,
    items: []pkt.ItemInstance,

    pub fn write(self: *const ContainerSetContentPacket, bs: *BitStream) !void {
        try bs.writeU8(self.window_id);
        try bs.writeU16(@intCast(self.items.len));
        for (self.items) |item| try item.write(bs);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !ContainerSetContentPacket {
        const window = try bs.readU8();
        const count = try bs.readU16();
        var items = try allocator.alloc(pkt.ItemInstance, count);
        errdefer allocator.free(items);
        for (0..count) |i| items[i] = try pkt.ItemInstance.read(bs);
        return .{ .window_id = window, .items = items };
    }

    pub fn deinit(self: *ContainerSetContentPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
    }
};
