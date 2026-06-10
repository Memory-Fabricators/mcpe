//! Sign update packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const SignUpdatePacket = struct {
    x: i16,
    y: i16,
    z: i16,
    lines: [4][]const u8,

    pub fn write(self: *const SignUpdatePacket, bs: *BitStream) !void {
        try bs.writeU16(@bitCast(self.x));
        try bs.writeU16(@bitCast(self.y));
        try bs.writeU16(@bitCast(self.z));
        for (self.lines) |line| try bs.writeString(line);
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !SignUpdatePacket {
        const x: i16 = @bitCast(try bs.readU16());
        const y: i16 = @bitCast(try bs.readU16());
        const z: i16 = @bitCast(try bs.readU16());
        var lines: [4][]const u8 = undefined;
        for (0..4) |i| lines[i] = try bs.readStringAlloc(allocator);
        return .{ .x = x, .y = y, .z = z, .lines = lines };
    }

    pub fn deinit(self: *SignUpdatePacket, allocator: std.mem.Allocator) void {
        for (self.lines) |line| allocator.free(line);
    }
};
