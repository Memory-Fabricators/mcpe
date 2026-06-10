//! Ready packet - sent by client after receiving login status / start game.

const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ReadyPacket = struct {
    pub fn write(_: *const ReadyPacket, _: *BitStream) !void {}
    pub fn read(_: *BitStream, _: std.mem.Allocator) !ReadyPacket {
        return .{};
    }
};

const std = @import("std");
