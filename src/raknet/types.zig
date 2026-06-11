//! Core types used by RakNet, ported from RakNetTypes.h, PacketPriority.h, etc.
//! Zig 0.16 port using std.Io interface.

const std = @import("std");
const io = std.Io;
const net = io.net;

/// RAKNET_PROTOCOL_VERSION
pub const protocol_version: u8 = 6;

/// Maximum number of local IP addresses supported
pub const max_internal_ids: usize = 10;

/// Maximum MTU size
pub const max_mtu_size: usize = 1492;
pub const min_mtu_size: usize = 400;

/// Default MTU size
pub const default_mtu_size: usize = 1400; // been 1400 for a while

/// Number of ordered streams
pub const num_ordered_streams: usize = 32; // 2^5

/// Size of ping times array
pub const ping_times_array_size: usize = 5;

/// Unassigned player index
pub const unassigned_player_index: u16 = 65535;

/// Unassigned network ID
pub const unassigned_network_id: u64 = @bitCast(@as(i64, -1));

/// Index of an invalid SystemAddress / RakNetGUID
pub const unassigned_system_index: u16 = 65535;

// ---------------------------------------------------------------------------
// Time types
// ---------------------------------------------------------------------------

/// Time in milliseconds (64-bit to avoid overflow)
pub const TimeMS = u64;

/// Time in microseconds
pub const TimeUS = u64;

/// Bit size type
pub const BitSize = u32;

/// System index
pub const SystemIndex = u16;

/// Network ID type
pub const NetworkID = u64;

/// Unique ID type
pub const UniqueIDType = u8;

/// RPC index
pub const RPCIndex = u8;

pub const max_rpc_map_size: u16 = (@as(u16, @intCast((@as(RPCIndex, 0) -% 1)))) - 1;
pub const undefined_rpc_index: RPCIndex = @as(RPCIndex, 0) -% 1;

/// Message ID is first byte
pub const MessageID = u8;

// ---------------------------------------------------------------------------
// Startup result
// ---------------------------------------------------------------------------

pub const StartupResult = enum(i32) {
    raknet_started = 0,
    raknet_already_started,
    invalid_socket_descriptors,
    invalid_max_connections,
    socket_family_not_supported,
    socket_port_already_in_use,
    socket_failed_to_bind,
    socket_failed_test_send,
    port_cannot_be_zero,
    failed_to_create_network_thread,
    startup_other_failure,
};

// ---------------------------------------------------------------------------
// Connection attempt result
// ---------------------------------------------------------------------------

pub const ConnectionAttemptResult = enum(i32) {
    connection_attempt_started = 0,
    invalid_parameter,
    cannot_resolve_domain_name,
    already_connected_to_endpoint,
    connection_attempt_already_in_progress,
    security_initialization_failed,
};

// ---------------------------------------------------------------------------
// Connection state
// ---------------------------------------------------------------------------

pub const ConnectionState = enum(u8) {
    /// Connect() was called, but the process hasn't started yet
    is_pending,
    /// Processing the connection attempt
    is_connecting,
    /// Is connected and able to communicate
    is_connected,
    /// Was connected, but will disconnect as soon as remaining messages are delivered
    is_disconnecting,
    /// A connection attempt failed and will be aborted
    is_silently_disconnecting,
    /// No longer connected
    is_disconnected,
    /// Was never connected, or disconnected long enough ago
    is_not_connected,
};

// ---------------------------------------------------------------------------
// Packet priority
// ---------------------------------------------------------------------------

pub const PacketPriority = enum(u8) {
    /// Highest priority - triggers immediate sends
    immediate_priority,
    /// For every 2 IMMEDIATE_PRIORITY messages, 1 HIGH_PRIORITY will be sent
    high_priority,
    /// For every 2 HIGH_PRIORITY messages, 1 MEDIUM_PRIORITY will be sent
    medium_priority,
    /// For every 2 MEDIUM_PRIORITY messages, 1 LOW_PRIORITY will be sent
    low_priority,
    /// Internal
    number_of_priorities,
};

// ---------------------------------------------------------------------------
// Packet reliability
// ---------------------------------------------------------------------------

pub const PacketReliability = enum(u8) {
    /// Same as regular UDP, discards duplicate datagrams.
    unreliable,
    /// Regular UDP with sequence counter. Out of order messages discarded.
    unreliable_sequenced,
    /// Reliable, but not necessarily in order.
    reliable,
    /// Reliable and ordered. Messages delayed waiting for out of order.
    reliable_ordered,
    /// Reliable and sequenced. Out of order messages dropped.
    reliable_sequenced,
    /// Same as UNRELIABLE, with ack receipt notification.
    unreliable_with_ack_receipt,
    /// Same as RELIABLE, with ack receipt notification.
    reliable_with_ack_receipt,
    /// Same as RELIABLE_ORDERED, with ack receipt notification.
    reliable_ordered_with_ack_receipt,
    /// Internal
    number_of_reliabilities,
};

// ---------------------------------------------------------------------------
// Public key mode
// ---------------------------------------------------------------------------

pub const PublicKeyMode = enum(u8) {
    /// Insecure connection
    insecure_connection,
    /// Accept whatever public key the server gives
    accept_any_public_key,
    /// Use a known remote server public key (recommended for secure connections)
    use_known_public_key,
    /// Use two-way authentication
    use_two_way_authentication,
};

// ---------------------------------------------------------------------------
// Public key
// ---------------------------------------------------------------------------

pub const PublicKey = struct {
    mode: PublicKeyMode = .insecure_connection,
    remote_server_public_key: ?[]const u8 = null,
    my_public_key: ?[]const u8 = null,
    my_private_key: ?[]const u8 = null,
};

// ---------------------------------------------------------------------------
// Socket descriptor
// ---------------------------------------------------------------------------

pub const SocketDescriptor = struct {
    /// The local port to bind to. 0 = OS autoassign.
    port: u16 = 0,
    /// The local network card address to bind to (e.g., "127.0.0.1"). Empty = INADDR_ANY.
    host_address: [32]u8 = @splat(0),
    /// IP version family
    socket_family: SocketFamily = .ipv4,
    /// Extra socket options
    extra_socket_options: u32 = 0,
};

pub const SocketFamily = enum(u16) {
    ipv4 = 2, // AF_INET
    ipv6 = 10, // AF_INET6 (varies by platform, but these are common values)
    unspecified = 0, // AF_UNSPEC
};

// ---------------------------------------------------------------------------
// SystemAddress
// ---------------------------------------------------------------------------

/// Network address for a system.
/// This is not necessarily a unique identifier - use RakNetGUID for that.
pub const SystemAddress = struct {
    /// The IP address + port using std.Io.net types
    ip: net.IpAddress = .{ .ip4 = .{ .bytes = .{ 0, 0, 0, 0 }, .port = 0 } },
    /// Used internally for fast lookup. Don't transmit this.
    system_index: SystemIndex = unassigned_system_index,

    /// Create an unassigned system address
    pub fn unassigned() SystemAddress {
        return .{
            .ip = .{ .ip4 = .{ .bytes = .{ 255, 255, 255, 255 }, .port = 65535 } },
            .system_index = unassigned_system_index,
        };
    }

    /// Create from IP string like "192.0.2.1" with optional port after '|'
    pub fn fromString(str: []const u8) !SystemAddress {
        if (std.mem.indexOfScalar(u8, str, '|')) |pipe_idx| {
            const ip_str = str[0..pipe_idx];
            const port_str = str[pipe_idx + 1 ..];
            const port = try std.fmt.parseInt(u16, port_str, 10);
            const ip = try net.IpAddress.parse(ip_str, port);
            return .{ .ip = ip };
        }
        const ip = try net.IpAddress.parse(str, 0);
        return .{ .ip = ip };
    }

    /// Create from IP string and explicit port
    pub fn fromStringExplicitPort(str: []const u8, port: u16) !SystemAddress {
        const ip = try net.IpAddress.parse(str, port);
        return .{ .ip = ip };
    }

    /// Get the port
    pub fn getPort(self: SystemAddress) u16 {
        return self.ip.getPort();
    }

    /// Set the port
    pub fn setPort(self: *SystemAddress, port: u16) void {
        self.ip.setPort(port);
    }

    /// Check if this is the unassigned address
    pub fn isUnassigned(self: SystemAddress) bool {
        return self.system_index == unassigned_system_index;
    }

    /// Check equality excluding port
    pub fn equalsExcludingPort(self: SystemAddress, other: SystemAddress) bool {
        return switch (self.ip) {
            .ip4 => |a| switch (other.ip) {
                .ip4 => |b| std.mem.eql(u8, &a.bytes, &b.bytes),
                else => false,
            },
            .ip6 => |a| switch (other.ip) {
                .ip6 => |b| std.mem.eql(u8, &a.bytes, &b.bytes),
                else => false,
            },
        };
    }

    /// Format to string "IP|Port"
    pub fn format(
        self: SystemAddress,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try self.ip.format("", .{}, writer);
    }
};

// ---------------------------------------------------------------------------
// RakNetGUID
// ---------------------------------------------------------------------------

/// Uniquely identifies an instance of RakPeer.
pub const RakNetGUID = struct {
    g: u64,
    system_index: SystemIndex = unassigned_system_index,

    /// Create an unassigned GUID
    pub fn unassigned() RakNetGUID {
        return .{ .g = @bitCast(@as(i64, -1)) };
    }

    /// Check if this is unassigned
    pub fn isUnassigned(self: RakNetGUID) bool {
        return self.g == @as(u64, @bitCast(@as(i64, -1)));
    }

    /// Format GUID as hex string
    pub fn format(
        self: RakNetGUID,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{x}", .{self.g});
    }
};

// ---------------------------------------------------------------------------
// AddressOrGUID
// ---------------------------------------------------------------------------

pub const AddressOrGUID = union(enum) {
    guid: RakNetGUID,
    address: SystemAddress,

    pub fn isUndefined(self: AddressOrGUID) bool {
        return switch (self) {
            .guid => |g| g.isUnassigned(),
            .address => |a| a.isUnassigned(),
        };
    }

    pub fn getSystemIndex(self: AddressOrGUID) SystemIndex {
        return switch (self) {
            .guid => |g| g.system_index,
            .address => |a| a.system_index,
        };
    }
};

// ---------------------------------------------------------------------------
// Packet
// ---------------------------------------------------------------------------

/// Represents a received user message from another system.
pub const Packet = struct {
    /// The system that sent this packet
    system_address: SystemAddress,
    /// Unique identifier for the system that sent this packet
    guid: RakNetGUID,
    /// The length of the data in bytes
    length: u32,
    /// The length of the data in bits
    bit_size: BitSize,
    /// The data from the sender
    data: []u8,
    /// If true, this message was generated locally (not from network)
    was_generated_locally: bool = false,
    /// Allocator used for the data buffer (when we own it)
    allocator: ?std.mem.Allocator = null,

    /// Deallocate the packet data
    pub fn deinit(self: *Packet) void {
        if (self.allocator) |alloc| {
            alloc.free(self.data);
            self.data = &.{};
            self.allocator = null;
        }
    }
};

// ---------------------------------------------------------------------------
// uint24_t equivalent
// ---------------------------------------------------------------------------

pub const Uint24 = packed struct(u32) {
    value: u24,

    pub fn init(v: anytype) Uint24 {
        return .{ .value = @intCast(v & 0xFFFFFF) };
    }

    pub fn toU32(self: Uint24) u32 {
        return @as(u32, self.value);
    }
};

// ---------------------------------------------------------------------------
// RakNetStatistics (simplified)
// ---------------------------------------------------------------------------

pub const RakNetStatistics = struct {
    /// The send rate target
    send_rate_target: u64 = 0,
    /// Connection time in ms
    connection_start_time: TimeMS = 0,
    /// Current sends per second
    sends_per_second: f64 = 0,
    /// Bits per second sent
    bits_per_second_sent: u64 = 0,
    /// Bits per second received
    bits_per_second_received: u64 = 0,
    /// Messages in send buffer
    messages_in_send_buffer: u32 = 0,
    /// Messages in resend buffer
    messages_in_resend_buffer: u32 = 0,
    /// Packet loss percentage
    packet_loss_percent: f64 = 0,
    /// Average ping
    average_ping: f64 = 0,
    /// Lowest ping
    lowest_ping: u32 = 0,
    /// MTU size
    mtu_size: u32 = default_mtu_size,
};
