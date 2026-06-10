//! Add mob packet - mob entity spawn with entity data.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const AddMobPacket = struct {
    entity_id: i32,
    entity_type: i32,
    x: f32,
    y: f32,
    z: f32,
    y_rot: i8,
    x_rot: i8,
    data: []u8,

    pub fn write(self: *const AddMobPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU32(@bitCast(self.entity_type));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
        try bs.writeU8(@bitCast(self.y_rot));
        try bs.writeU8(@bitCast(self.x_rot));
        try bs.writeU16(@intCast(self.data.len));
        if (self.data.len > 0) try bs.writeAlignedBytes(self.data);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !AddMobPacket {
        const id: i32 = @bitCast(try bs.readU32());
        const etype: i32 = @bitCast(try bs.readU32());
        const data_len = try bs.readU16();
        const data = if (data_len > 0) try bs.readBytesAlloc(allocator) else &.{};
        return .{
            .entity_id = id,
            .entity_type = etype,
            .x = try bs.readF32(),
            .y = try bs.readF32(),
            .z = try bs.readF32(),
            .y_rot = @bitCast(try bs.readU8()),
            .x_rot = @bitCast(try bs.readU8()),
            .data = data,
        };
    }

    pub fn deinit(self: *AddMobPacket, allocator: std.mem.Allocator) void {
        if (self.data.len > 0) allocator.free(self.data);
    }
};
