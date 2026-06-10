//! Explode packet.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const TilePos = struct {
    x: i32,
    y: i32,
    z: i32,
};

pub const ExplodePacket = struct {
    x: f32,
    y: f32,
    z: f32,
    radius: f32,
    records: []TilePos,

    pub fn write(self: *const ExplodePacket, bs: *BitStream) !void {
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
        try bs.writeF32(self.radius);
        const xp: i32 = @intFromFloat(self.x);
        const yp: i32 = @intFromFloat(self.y);
        const zp: i32 = @intFromFloat(self.z);
        try bs.writeU32(@intCast(self.records.len));
        for (self.records) |tp| {
            try bs.writeU8(@bitCast(@as(i8, @intCast(tp.x - xp))));
            try bs.writeU8(@bitCast(@as(i8, @intCast(tp.y - yp))));
            try bs.writeU8(@bitCast(@as(i8, @intCast(tp.z - zp))));
        }
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !ExplodePacket {
        const x = try bs.readF32();
        const y = try bs.readF32();
        const z = try bs.readF32();
        const radius = try bs.readF32();
        const xp: i32 = @intFromFloat(x);
        const yp: i32 = @intFromFloat(y);
        const zp: i32 = @intFromFloat(z);
        const count = try bs.readU32();
        var records = try allocator.alloc(TilePos, count);
        errdefer allocator.free(records);
        for (0..count) |i| {
            const dx: i8 = @bitCast(try bs.readU8());
            const dy: i8 = @bitCast(try bs.readU8());
            const dz: i8 = @bitCast(try bs.readU8());
            records[i] = .{
                .x = xp + dx,
                .y = yp + dy,
                .z = zp + dz,
            };
        }
        return .{ .x = x, .y = y, .z = z, .radius = radius, .records = records };
    }

    pub fn deinit(self: *ExplodePacket, allocator: std.mem.Allocator) void {
        allocator.free(self.records);
    }
};
