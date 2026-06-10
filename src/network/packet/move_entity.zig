//! Move entity packet - generic entity movement.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const MoveEntityPacket = struct {
    entity_id: i32,
    x: f32,
    y: f32,
    z: f32,
    y_rot: f32,
    x_rot: f32,

    pub fn init(id: i32, x: f32, y: f32, z: f32, y_rot: f32, x_rot: f32) MoveEntityPacket {
        return .{ .entity_id = id, .x = x, .y = y, .z = z, .y_rot = y_rot, .x_rot = x_rot };
    }

    pub fn write(self: *const MoveEntityPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
        try bs.writeF32(self.y_rot);
        try bs.writeF32(self.x_rot);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !MoveEntityPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .x = try bs.readF32(),
            .y = try bs.readF32(),
            .z = try bs.readF32(),
            .y_rot = try bs.readF32(),
            .x_rot = try bs.readF32(),
        };
    }
};
