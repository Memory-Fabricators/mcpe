//! Container ack packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ContainerAckPacket = struct {
    window_id: u8,

    pub fn write(self: *const ContainerAckPacket, bs: *BitStream) !void {
        try bs.writeU8(self.window_id);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !ContainerAckPacket {
        return .{ .window_id = try bs.readU8() };
    }
};
