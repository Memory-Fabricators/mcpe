//! Update block packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const UpdateBlockPacket = struct {
    x: i32,
    y: i32,
    z: i32,
    block_id: u8,
    block_data: u8,

    pub fn write(self: *const UpdateBlockPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.x));
        try bs.writeU32(@bitCast(self.y));
        try bs.writeU32(@bitCast(self.z));
        try bs.writeU8(self.block_id);
        try bs.writeU8(self.block_data);
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !UpdateBlockPacket {
        return .{
            .x = @bitCast(try bs.readU32()),
            .y = @bitCast(try bs.readU32()),
            .z = @bitCast(try bs.readU32()),
            .block_id = try bs.readU8(),
            .block_data = try bs.readU8(),
        };
    }
};
