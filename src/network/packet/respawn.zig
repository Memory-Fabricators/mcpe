//! Respawn packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const RespawnPacket = struct {
    entity_id: i32,
    x: f32,
    y: f32,
    z: f32,

    pub fn write(self: *const RespawnPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !RespawnPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .x = try bs.readF32(),
            .y = try bs.readF32(),
            .z = try bs.readF32(),
        };
    }
};
