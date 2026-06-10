//! Message packet - chat message.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const MessagePacket = struct {
    message: []const u8,

    pub fn init(msg: []const u8) MessagePacket {
        return .{ .message = msg };
    }

    pub fn write(self: *const MessagePacket, bs: *BitStream) !void {
        try bs.writeString(self.message);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !MessagePacket {
        return .{ .message = try bs.readStringAlloc(allocator) };
    }

    pub fn deinit(self: *MessagePacket, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};
