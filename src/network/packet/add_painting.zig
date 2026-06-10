//! Add painting packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const AddPaintingPacket = struct {
    entity_id: i32,
    x: i32,
    y: i32,
    z: i32,
    direction: i32,
    title: []const u8,

    pub fn write(self: *const AddPaintingPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU32(@bitCast(self.direction));
        try bs.writeString(self.title);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !AddPaintingPacket {
        return .{
            .entity_id = @bitCast(try bs.readU32()),
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
            .direction = @bitCast(try bs.readU32()),
            .title = try bs.readStringAlloc(allocator),
        };
    }

    pub fn deinit(self: *AddPaintingPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
    }
};
