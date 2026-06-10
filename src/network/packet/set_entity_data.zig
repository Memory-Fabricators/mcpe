//! Set entity data packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const SetEntityDataPacket = struct {
    entity_id: i32,
    /// Packed entity data as raw bytes
    data: []u8,

    pub fn write(self: *const SetEntityDataPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU16(@intCast(self.data.len));
        if (self.data.len > 0) try bs.writeAlignedBytes(self.data);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !SetEntityDataPacket {
        const id: i32 = @bitCast(try bs.readU32());
        const len = try bs.readU16();
        const data = if (len > 0) try bs.readBytesAlloc(allocator) else &.{};
        return .{ .entity_id = id, .data = data };
    }

    pub fn deinit(self: *SetEntityDataPacket, allocator: std.mem.Allocator) void {
        if (self.data.len > 0) allocator.free(self.data);
    }
};
