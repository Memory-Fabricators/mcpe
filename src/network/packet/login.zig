//! Login packet - first packet sent by client after connection.

const std = @import("std");
const raknet = @import("raknet");
const BitStream = raknet.BitStream;

pub const LoginPacket = struct {
    client_name: []const u8,
    client_network_version: i32,
    client_network_lowest_supported_version: i32,

    pub fn init(name: []const u8, version: i32) LoginPacket {
        return .{
            .client_name = name,
            .client_network_version = version,
            .client_network_lowest_supported_version = version,
        };
    }

    pub fn write(self: *const LoginPacket, bs: *BitStream) !void {
        try bs.writeString(self.client_name);
        try bs.writeU32(@bitCast(self.client_network_version));
        try bs.writeU32(@bitCast(self.client_network_lowest_supported_version));
    }

    pub fn read(bs: *BitStream, allocator: std.mem.Allocator) !LoginPacket {
        const name = try bs.readStringAlloc(allocator);
        errdefer allocator.free(name);
        const has_more = bs.getNumberOfUnreadBits() > 0;
        if (has_more) {
            return .{
                .client_name = name,
                .client_network_version = @bitCast(try bs.readU32()),
                .client_network_lowest_supported_version = @bitCast(try bs.readU32()),
            };
        }
        return .{
            .client_name = name,
            .client_network_version = -1,
            .client_network_lowest_supported_version = -1,
        };
    }

    pub fn deinit(self: *LoginPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.client_name);
    }
};
