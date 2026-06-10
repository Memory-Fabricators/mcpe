//! Start game packet - tells the client to begin playing.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const StartGamePacket = struct {
    level_seed: i64,
    level_generator_version: i32,
    game_type: i32,
    entity_id: i32,
    x: f32,
    y: f32,
    z: f32,

    pub fn init(seed: i64, gen_ver: i32, game_type: i32, entity_id: i32, x: f32, y: f32, z: f32) StartGamePacket {
        return .{
            .level_seed = seed,
            .level_generator_version = gen_ver,
            .game_type = game_type,
            .entity_id = entity_id,
            .x = x,
            .y = y,
            .z = z,
        };
    }

    pub fn write(self: *const StartGamePacket, bs: *BitStream) !void {
        try bs.writeU64(@bitCast(self.level_seed));
        try bs.writeU32(@bitCast(self.level_generator_version));
        try bs.writeU32(@bitCast(self.game_type));
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !StartGamePacket {
        return .{
            .level_seed = @bitCast(try bs.readU64()),
            .level_generator_version = @bitCast(try bs.readU32()),
            .game_type = @bitCast(try bs.readU32()),
            .entity_id = @bitCast(try bs.readU32()),
            .x = try bs.readF32(),
            .y = try bs.readF32(),
            .z = try bs.readF32(),
        };
    }
};
