//! Chat packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ChatPacket = struct {
    message: []const u8,

    pub fn init(msg: []const u8) ChatPacket {
        return .{ .message = msg };
    }

    pub fn write(self: *const ChatPacket, bs: *BitStream) !void {
        try bs.writeString(self.message);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !ChatPacket {
        return .{ .message = try bs.readStringAlloc(allocator) };
    }

    pub fn deinit(self: *ChatPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.message);
    }
};
