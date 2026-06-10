//! Container open packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const ContainerOpenPacket = struct {
    window_id: u8,
    container_type: u8,
    slot_count: i16,
    x: i32,
    y: i32,
    z: i32,

    pub fn write(self: *const ContainerOpenPacket, bs: *BitStream) !void {
        try bs.writeU8(self.window_id);
        try bs.writeU8(self.container_type);
        try bs.writeU16(@bitCast(self.slot_count));
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !ContainerOpenPacket {
        return .{
            .window_id = try bs.readU8(),
            .container_type = try bs.readU8(),
            .slot_count = @bitCast(try bs.readU16()),
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
        };
    }
};
