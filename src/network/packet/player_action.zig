//! Player action packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const PlayerActionPacket = struct {
    action: i32,
    x: i32,
    y: i32,
    z: i32,
    face: i32,
    entity_id: i32,

    pub fn write(self: *const PlayerActionPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.action));
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU32(@bitCast(self.face));
        try bs.writeU32(@bitCast(self.entity_id));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !PlayerActionPacket {
        return .{
            .action = @bitCast(try bs.readU32()),
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
            .face = @bitCast(try bs.readU32()),
            .entity_id = @bitCast(try bs.readU32()),
        };
    }
};
