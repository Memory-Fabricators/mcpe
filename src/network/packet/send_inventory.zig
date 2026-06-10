//! Send inventory packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;
const pkt = @import("../packet.zig");

pub const SendInventoryPacket = struct {
    entity_id: i32,
    window_id: u8,
    items: []pkt.ItemInstance,
    hotbar: []pkt.ItemInstance,

    pub fn write(self: *const SendInventoryPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU8(self.window_id);
        try bs.writeU16(@intCast(self.items.len));
        for (self.items) |item| try item.write(bs);
        try bs.writeU16(@intCast(self.hotbar.len));
        for (self.hotbar) |item| try item.write(bs);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !SendInventoryPacket {
        const eid: i32 = @bitCast(try bs.readU32());
        const window = try bs.readU8();
        const item_count = try bs.readU16();
        var items = try allocator.alloc(pkt.ItemInstance, item_count);
        errdefer allocator.free(items);
        for (0..item_count) |i| items[i] = try pkt.ItemInstance.read(bs);
        const hotbar_count = try bs.readU16();
        var hotbar = try allocator.alloc(pkt.ItemInstance, hotbar_count);
        errdefer allocator.free(hotbar);
        for (0..hotbar_count) |i| hotbar[i] = try pkt.ItemInstance.read(bs);
        return .{ .entity_id = eid, .window_id = window, .items = items, .hotbar = hotbar };
    }

    pub fn deinit(self: *SendInventoryPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.items);
        allocator.free(self.hotbar);
    }
};
