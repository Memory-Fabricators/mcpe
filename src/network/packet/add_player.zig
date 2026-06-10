//! Add player packet - adds another player to the client's world.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;
const RakNetGUID = raknet.RakNetGUID;
const pkt = @import("../packet.zig");

pub const AddPlayerPacket = struct {
    owner: RakNetGUID,
    name: []const u8,
    entity_id: i32,
    x: f32,
    y: f32,
    z: f32,
    y_rot: i8,
    x_rot: i8,
    carried_item_id: i16,
    carried_item_aux_value: i16,

    pub fn write(self: *const AddPlayerPacket, bs: *BitStream) !void {
        try bs.writeU64(self.owner.g);
        try bs.writeString(self.name);
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
        try bs.writeU8(@bitCast(self.y_rot));
        try bs.writeU8(@bitCast(self.x_rot));
        try bs.writeU16(@bitCast(self.carried_item_id));
        try bs.writeU16(@bitCast(self.carried_item_aux_value));
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !AddPlayerPacket {
        const owner = RakNetGUID{ .g = try bs.readU64() };
        const name = try bs.readStringAlloc(allocator);
        errdefer allocator.free(name);
        return .{
            .owner = owner,
            .name = name,
            .entity_id = @bitCast(try bs.readU32()),
            .x = try bs.readF32(),
            .y = try bs.readF32(),
            .z = try bs.readF32(),
            .y_rot = @bitCast(try bs.readU8()),
            .x_rot = @bitCast(try bs.readU8()),
            .carried_item_id = @bitCast(try bs.readU16()),
            .carried_item_aux_value = @bitCast(try bs.readU16()),
        };
    }

    pub fn deinit(self: *AddPlayerPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};
