//! Animate packet - swing arm, etc.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const AnimatePacket = struct {
    action: u8,
    entity_id: i32,

    pub fn write(self: *const AnimatePacket, bs: *BitStream) !void {
        try bs.writeU8(self.action);
        try bs.writeU32(@bitCast(self.entity_id));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !AnimatePacket {
        return .{
            .action = try bs.readU8(),
            .entity_id = @bitCast(try bs.readU32()),
        };
    }
};
