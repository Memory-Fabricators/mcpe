//! Take item entity packet - picking up an item.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const TakeItemEntityPacket = struct {
    target: i32,
    entity_id: i32,

    pub fn init(target: i32, entity_id: i32) TakeItemEntityPacket {
        return .{ .target = target, .entity_id = entity_id };
    }

    pub fn write(self: *const TakeItemEntityPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.target));
        try bs.writeU32(@bitCast(self.entity_id));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !TakeItemEntityPacket {
        return .{
            .target = @bitCast(try bs.readU32()),
            .entity_id = @bitCast(try bs.readU32()),
        };
    }
};
