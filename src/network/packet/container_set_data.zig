//! Container set data packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ContainerSetDataPacket = struct {
    window_id: u8,
    property: i16,
    value: i16,

    pub fn write(self: *const ContainerSetDataPacket, bs: *BitStream) !void {
        try bs.writeU8(self.window_id);
        try bs.writeU16(@bitCast(self.property));
        try bs.writeU16(@bitCast(self.value));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !ContainerSetDataPacket {
        return .{
            .window_id = try bs.readU8(),
            .property = @bitCast(try bs.readU16()),
            .value = @bitCast(try bs.readU16()),
        };
    }
};
