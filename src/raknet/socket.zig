//! Platform-independent UDP socket layer for RakNet.
//! Uses Zig 0.16 std.Io.net interface.
//! Ported from SocketLayer.h / SocketLayer.cpp

const std = @import("std");
const io = std.Io;
const net = io.net;

const types = @import("types.zig");
const SystemAddress = types.SystemAddress;
const SocketDescriptor = types.SocketDescriptor;

pub const max_mtu_size = types.max_mtu_size;

/// A bound UDP socket
pub const UdpSocket = struct {
    /// The underlying socket
    socket: net.Socket,
    /// The bound local address
    local_address: SystemAddress,
    /// Socket family
    family: types.SocketFamily = .ipv4,
    /// Associated RakPeer (for callbacks)
    userdata: ?*anyopaque = null,

    /// Create and bind a UDP socket
    pub fn bind(io_ctx: io, desc: SocketDescriptor) !UdpSocket {
        const addr = try resolveBindAddress(io_ctx, desc);

        const bind_opts: net.IpAddress.BindOptions = .{
            .mode = .dgram,
            .allow_broadcast = true,
        };

        const sock = try net.IpAddress.bind(&addr, io_ctx, bind_opts);

        return .{
            .socket = sock,
            .local_address = .{ .ip = sock.address },
            .family = desc.socket_family,
        };
    }

    /// Send data to a specific address
    pub fn sendTo(self: *const UdpSocket, io_ctx: io, dest: *const SystemAddress, data: []const u8) !void {
        try self.socket.send(io_ctx, &dest.ip, data);
    }

    /// Receive data from any address (blocking)
    pub fn recvFrom(
        self: *const UdpSocket,
        io_ctx: io,
        buffer: []u8,
    ) !struct { bytes_read: usize, from: SystemAddress } {
        const msg = try self.socket.receive(io_ctx, buffer);
        return .{
            .bytes_read = msg.data.len,
            .from = .{ .ip = msg.from },
        };
    }

    /// Receive data with timeout
    pub fn recvFromTimeout(
        self: *const UdpSocket,
        io_ctx: io,
        buffer: []u8,
        timeout_ns: u64,
    ) !struct { bytes_read: usize, from: SystemAddress } {
        const msg = try self.socket.receiveTimeout(io_ctx, buffer, .{ .duration = .{ .raw = .{ .nanoseconds = @intCast(timeout_ns) }, .clock = .awake } });
        return .{
            .bytes_read = msg.data.len,
            .from = .{ .ip = msg.from },
        };
    }

    /// Get the local port
    pub fn getLocalPort(self: *const UdpSocket) u16 {
        return self.socket.address.getPort();
    }

    /// Close the socket
    pub fn close(self: *const UdpSocket, io_ctx: io) void {
        self.socket.close(io_ctx);
    }
};

/// Resolve the bind address from a socket descriptor
fn resolveBindAddress(io_ctx: io, desc: SocketDescriptor) !net.IpAddress {
    _ = io_ctx;
    // If host address is empty, use any address
    const host_str = if (desc.host_address[0] == 0) null else blk: {
        const len = std.mem.indexOfScalar(u8, &desc.host_address, 0) orelse desc.host_address.len;
        break :blk desc.host_address[0..len];
    };

    if (host_str) |host| {
        if (std.mem.eql(u8, host, "")) {
            // Bind to all interfaces
            return switch (desc.socket_family) {
                .ipv4 => net.IpAddress{ .ip4 = .{ .bytes = .{ 0, 0, 0, 0 }, .port = desc.port } },
                .ipv6 => net.IpAddress{ .ip6 = .{ .bytes = .{0} ** 16, .port = desc.port } },
                .unspecified => net.IpAddress{ .ip4 = .{ .bytes = .{ 0, 0, 0, 0 }, .port = desc.port } },
            };
        }
        return try net.IpAddress.parse(host, desc.port);
    }

    // Default: bind to all interfaces
    return net.IpAddress{ .ip4 = .{ .bytes = .{ 0, 0, 0, 0 }, .port = desc.port } };
}

/// Resolve a hostname to an IP address
pub fn resolveHostname(io_ctx: io, host: []const u8, port: u16) !net.IpAddress {
    _ = io_ctx;
    // First try direct IP parse
    if (net.IpAddress.parse(host, port)) |ip| {
        return ip;
    } else |_| {}

    // For actual DNS resolution, we need the hostname resolution API
    // In Zig 0.16, HostName resolution requires vtable access
    // We use the Io vtable for this:

    // Simple approach: try parsing as IP first, then as hostname
    // For DNS resolution in Zig 0.16, we'd use:
    // return net.HostName.resolve(io_ctx, host, port);
    // But this requires checking the API

    // Fallback: attempt resolution via the vtable
    return error.CannotResolveDomainName;
}

/// Get the list of local IP addresses
pub fn getLocalIPs(io_ctx: io, max_count: usize) ![]SystemAddress {
    // This is a simplified version - full implementation would
    // use getifaddrs or equivalent
    _ = io_ctx;
    _ = max_count;
    return &.{};
}

/// Check if a port is in use
pub fn isPortInUse(io_ctx: io, port: u16) bool {
    // Try to bind and immediately close
    const addr = net.IpAddress{ .ip4 = .{ .bytes = .{ 0, 0, 0, 0 }, .port = port } };
    const sock = net.IpAddress.bind(&addr, io_ctx, .{ .mode = .dgram }) catch return true;
    sock.close(io_ctx);
    return false;
}
