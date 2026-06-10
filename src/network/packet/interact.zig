//! Interact packet - player interaction with entity.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const InteractPacket = struct {
    action: u8,
    entity_id: i32,
    target_id: i32,

    pub fn write(self: *const InteractPacket, bs: *BitStream) !void {
        try bs.writeU8(self.action);
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU32(@bitCast(self.target_id));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !InteractPacket {
        return .{
            .action = try bs.readU8(),
            .entity_id = @bitCast(try bs.readU32()),
            .target_id = @bitCast(try bs.readU32()),
        };
    }
};
