//! Container close packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ContainerClosePacket = struct {
    window_id: u8,

    pub fn init(id: u8) ContainerClosePacket {
        return .{ .window_id = id };
    }

    pub fn write(self: *const ContainerClosePacket, bs: *BitStream) !void {
        try bs.writeU8(self.window_id);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !ContainerClosePacket {
        return .{ .window_id = try bs.readU8() };
    }
};
