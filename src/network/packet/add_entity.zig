//! Add entity packet - generic entity spawn.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const AddEntityPacket = struct {
    entity_id: i32,
    entity_type: i32,
    x: f32,
    y: f32,
    z: f32,
    has_motion: bool,
    xd: i16,
    yd: i16,
    zd: i16,

    pub fn write(self: *const AddEntityPacket, bs: *BitStream) !void {
        try bs.writeU32(@bitCast(self.entity_id));
        try bs.writeU32(@bitCast(self.entity_type));
        try bs.writeF32(self.x);
        try bs.writeF32(self.y);
        try bs.writeF32(self.z);
        try bs.writeBool(self.has_motion);
        if (self.has_motion) {
            try bs.writeU16(@bitCast(self.xd));
            try bs.writeU16(@bitCast(self.yd));
            try bs.writeU16(@bitCast(self.zd));
        }
    }

    pub fn read(bs: *BitStream, _: std.mem.Allocator) !AddEntityPacket {
        const id: i32 = @bitCast(try bs.readU32());
        const etype: i32 = @bitCast(try bs.readU32());
        const x = try bs.readF32();
        const y = try bs.readF32();
        const z = try bs.readF32();
        const has_motion = try bs.readBool();
        var xd: i16 = 0;
        var yd: i16 = 0;
        var zd: i16 = 0;
        if (has_motion) {
            xd = @bitCast(try bs.readU16());
            yd = @bitCast(try bs.readU16());
            zd = @bitCast(try bs.readU16());
        }
        return .{
            .entity_id = id,
            .entity_type = etype,
            .x = x,
            .y = y,
            .z = z,
            .has_motion = has_motion,
            .xd = xd,
            .yd = yd,
            .zd = zd,
        };
    }
};
