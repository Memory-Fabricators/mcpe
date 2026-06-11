//! RakPeer - the main network interface.
//! Ported from RakPeer.h / RakPeer.cpp
//! Zig 0.16

const std = @import("std");
const io = std.Io;
const net = io.net;

const types = @import("types.zig");
const message_ids = @import("message_ids.zig");
const bitstream = @import("bitstream.zig");
const socket_mod = @import("socket.zig");

const ManagedList = std.array_list.Managed;

const SystemAddress = types.SystemAddress;
const RakNetGUID = types.RakNetGUID;
const AddressOrGUID = types.AddressOrGUID;
const Packet = types.Packet;
const PacketPriority = types.PacketPriority;
const PacketReliability = types.PacketReliability;
const SocketDescriptor = types.SocketDescriptor;
const StartupResult = types.StartupResult;
const ConnectionAttemptResult = types.ConnectionAttemptResult;
const ConnectionState = types.ConnectionState;
const TimeMS = types.TimeMS;
const BitStream = bitstream.BitStream;
const MessageId = message_ids.MessageId;

/// Maximum connections
const default_max_connections: u16 = 32;

/// Max incoming connections (0 = server mode off)
const default_max_incoming: u16 = 0;

/// Receive buffer size
const recv_buffer_size: usize = types.max_mtu_size * 2;

/// Internal connection info
const Connection = struct {
    /// Remote system address
    address: SystemAddress,
    /// Remote GUID
    guid: RakNetGUID,
    /// Connection state
    state: ConnectionState,
    /// When connection started
    connect_time: TimeMS,
    /// How many connection attempts made
    connection_attempts: u32,
    /// Last time we sent a connection attempt
    last_attempt_time: TimeMS,
    /// The system index
    system_index: u16,
    /// Timeout time in ms
    timeout_time: TimeMS,
    /// Average ping
    average_ping: f64,
    /// Last ping
    last_ping: u32,
    /// Lowest ping
    lowest_ping: u32,
    /// MTU size
    mtu_size: u32,
    /// Whether we initiated the connection
    we_initiated: bool,
    /// Password data (for incoming connections)
    password: ?[]u8,
};

/// Incoming packet queue entry
const PacketQueueEntry = struct {
    packet: Packet,
};

/// Ban list entry
const BanEntry = struct {
    ip_pattern: []const u8,
    ban_time: TimeMS, // 0 = permanent
};

/// Configuration for RakPeer
pub const Config = struct {
    /// Maximum number of connections
    max_connections: u16 = default_max_connections,
    /// Socket descriptors for binding
    sockets: []const SocketDescriptor,
    /// Thread priority (platform specific)
    thread_priority: i32 = -99999,
};

/// The main RakPeer network interface.
pub const RakPeer = struct {
    /// Allocator
    allocator: std.mem.Allocator,
    /// IO context (for networking + time)
    io: io,
    /// Whether the peer is started
    is_active: bool,
    /// My GUID
    my_guid: RakNetGUID,
    /// Bound UDP sockets
    sockets: ManagedList(socket_mod.UdpSocket),
    /// Connections array
    connections: ManagedList(Connection),
    /// Maximum incoming connections allowed
    max_incoming_connections: u16,
    /// Incoming password data
    incoming_password: ?[]u8,
    /// Incoming packet queue
    packet_queue: ManagedList(PacketQueueEntry),
    /// Ban list
    ban_list: ManagedList(BanEntry),
    /// Whether to limit IP connection frequency
    limit_ip_frequency: bool,
    /// Whether occasional pinging is enabled
    occasional_ping: bool,
    /// Timeout time in ms
    default_timeout_time: TimeMS,
    /// Next send receipt number
    next_send_receipt: u32,
    /// Offline ping response data
    offline_ping_data: ?[]u8,
    /// Start time
    start_time: TimeMS,
    /// IO context (lazy, set by startup)
    io_context: ?io,
    /// Incoming data buffer
    recv_buffer: [recv_buffer_size]u8,

    const Self = @This();

    /// Initialize a new RakPeer
    pub fn init(allocator: std.mem.Allocator, io_ctx: io) Self {
        return .{
            .allocator = allocator,
            .io = io_ctx,
            .is_active = false,
            .my_guid = RakNetGUID.unassigned(),
            .sockets = ManagedList(socket_mod.UdpSocket).init(allocator),
            .connections = ManagedList(Connection).init(allocator),
            .max_incoming_connections = default_max_incoming,
            .incoming_password = null,
            .packet_queue = ManagedList(PacketQueueEntry).init(allocator),
            .ban_list = ManagedList(BanEntry).init(allocator),
            .limit_ip_frequency = false,
            .occasional_ping = true,
            .default_timeout_time = 10000,
            .next_send_receipt = 0,
            .offline_ping_data = null,
            .start_time = 0,
            .io_context = null,
            .recv_buffer = @splat(0),
        };
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self) void {
        self.shutdown(0, 0, .low_priority);

        if (self.incoming_password) |pw| {
            self.allocator.free(pw);
            self.incoming_password = null;
        }
        if (self.offline_ping_data) |data| {
            self.allocator.free(data);
            self.offline_ping_data = null;
        }

        // Free ban list patterns
        for (self.ban_list.items) |entry| {
            self.allocator.free(entry.ip_pattern);
        }
        self.ban_list.deinit();

        self.sockets.deinit();
        self.connections.deinit();
        self.packet_queue.deinit();
    }

    // -----------------------------------------------------------------------
    // Startup / Shutdown
    // -----------------------------------------------------------------------

    /// Start the network threads and open listen ports.
    /// The IO context was already provided in init().
    pub fn startup(self: *Self, config: Config) !StartupResult {
        if (self.is_active) return .raknet_already_started;

        if (config.max_connections == 0) return .invalid_max_connections;
        if (config.sockets.len == 0) return .invalid_socket_descriptors;

        // Generate GUID (use stack pointer as entropy seed)
        var stack_var: u8 = 0;
        var rng = std.Random.DefaultPrng.init(@intFromPtr(&stack_var));
        self.my_guid = .{ .g = rng.random().int(u64) };

        // Bind sockets
        for (config.sockets) |desc| {
            const sock = socket_mod.UdpSocket.bind(self.io, desc) catch |err| {
                std.log.err("Failed to bind socket (port {}): {}", .{ desc.port, err });
                self.cleanupSockets();
                return switch (err) {
                    error.AddressInUse => .socket_port_already_in_use,
                    error.AddressUnavailable => .socket_failed_to_bind,
                    else => .socket_failed_to_bind,
                };
            };
            try self.sockets.append(sock);
        }

        self.is_active = true;
        self.start_time = getTimeMs(self.io);
        self.connections.clearRetainingCapacity();

        return .raknet_started;
    }

    /// Stop the network threads and close all connections.
    pub fn shutdown(
        self: *Self,
        block_duration_ms: u32,
        ordering_channel: u8,
        disconnect_priority: PacketPriority,
    ) void {
        _ = block_duration_ms;
        _ = ordering_channel;
        _ = disconnect_priority;

        if (!self.is_active) return;
        self.is_active = false;

        // Send disconnection notifications to all connected peers
        for (self.connections.items) |*conn| {
            if (conn.state == .is_connected) {
                conn.state = .is_disconnecting;
            }
        }

        // Close all sockets
        self.cleanupSockets();
    }

    fn cleanupSockets(self: *Self) void {
        for (self.sockets.items) |s| {
            s.close(self.io);
        }
        self.sockets.clearRetainingCapacity();
    }

    // -----------------------------------------------------------------------
    // Connection Management
    // -----------------------------------------------------------------------

    /// Connect to a remote host.
    pub fn connect(
        self: *Self,
        host: []const u8,
        remote_port: u16,
        password_data: ?[]const u8,
        send_attempts: u32,
        attempt_interval_ms: u32,
        timeout_ms: TimeMS,
    ) !ConnectionAttemptResult {
        if (!self.is_active) return error.NotStarted;

        // Resolve hostname
        const addr = blk: {
            if (net.IpAddress.parse(host, remote_port)) |ip| {
                break :blk ip;
            } else |_| {
                // Try DNS resolution
                if (self.resolveHostname(host, remote_port)) |ip| {
                    break :blk ip;
                } else |_| {
                    return .cannot_resolve_domain_name;
                }
            }
        };

        const remote = SystemAddress{ .ip = addr };

        // Check if already connected
        for (self.connections.items) |conn| {
            if (conn.state == .is_connected and conn.address.equalsExcludingPort(remote) and
                conn.address.getPort() == remote.getPort())
            {
                return .already_connected_to_endpoint;
            }
            if (conn.state == .is_connecting and conn.address.equalsExcludingPort(remote) and
                conn.address.getPort() == remote.getPort())
            {
                return .connection_attempt_already_in_progress;
            }
        }

        // Add new connection
        const now: TimeMS = getTimeMs(self.io);
        const conn = Connection{
            .address = remote,
            .guid = RakNetGUID.unassigned(),
            .state = .is_connecting,
            .connect_time = now,
            .connection_attempts = 0,
            .last_attempt_time = 0,
            .system_index = @intCast(self.connections.items.len),
            .timeout_time = if (timeout_ms > 0) timeout_ms else self.default_timeout_time,
            .average_ping = -1,
            .last_ping = 0,
            .lowest_ping = 0,
            .mtu_size = types.default_mtu_size,
            .we_initiated = true,
            .password = if (password_data) |pw| blk: {
                const copy = try self.allocator.alloc(u8, pw.len);
                @memcpy(copy, pw);
                break :blk copy;
            } else null,
        };

        try self.connections.append(conn);

        // Send open connection request
        try self.sendOpenConnectionRequest1(remote, send_attempts, attempt_interval_ms);

        return .connection_attempt_started;
    }

    /// Set maximum incoming connections
    pub fn setMaximumIncomingConnections(self: *Self, count: u16) void {
        self.max_incoming_connections = count;
    }

    /// Get maximum incoming connections
    pub fn getMaximumIncomingConnections(self: *Self) u16 {
        return self.max_incoming_connections;
    }

    /// Get number of active connections
    pub fn numberOfConnections(self: *Self) u16 {
        var count: u16 = 0;
        for (self.connections.items) |conn| {
            if (conn.state == .is_connected) count += 1;
        }
        return count;
    }

    /// Check if a system is banned
    pub fn isBanned(self: *Self, ip: []const u8) bool {
        for (self.ban_list.items) |entry| {
            if (matchIPPattern(ip, entry.ip_pattern)) {
                if (entry.ban_time == 0) return true;
                // Check if temporary ban has expired
                const now: TimeMS = getTimeMs(self.io);
                if (now < entry.ban_time) return true;
            }
        }
        return false;
    }

    /// Add an IP to the ban list
    pub fn addToBanList(self: *Self, ip: []const u8, duration_ms: TimeMS) !void {
        const copy = try self.allocator.alloc(u8, ip.len);
        @memcpy(copy, ip);
        const expire_time: TimeMS = if (duration_ms == 0) 0 else blk: {
            const now: TimeMS = getTimeMs(self.io);
            break :blk now + duration_ms;
        };
        try self.ban_list.append(.{ .ip_pattern = copy, .ban_time = expire_time });
    }

    /// Remove an IP from the ban list
    pub fn removeFromBanList(self: *Self, ip: []const u8) void {
        var i: usize = 0;
        while (i < self.ban_list.items.len) {
            if (std.mem.eql(u8, self.ban_list.items[i].ip_pattern, ip)) {
                self.allocator.free(self.ban_list.items[i].ip_pattern);
                _ = self.ban_list.swapRemove(i);
            } else {
                i += 1;
            }
        }
    }

    /// Clear the ban list
    pub fn clearBanList(self: *Self) void {
        for (self.ban_list.items) |entry| {
            self.allocator.free(entry.ip_pattern);
        }
        self.ban_list.clearRetainingCapacity();
    }

    /// Close a connection to another host
    pub fn closeConnection(
        self: *Self,
        target: AddressOrGUID,
        send_notification: bool,
        ordering_channel: u8,
        disconnect_priority: PacketPriority,
    ) void {
        for (self.connections.items) |*conn| {
            const matches = switch (target) {
                .address => |a| conn.address.equalsExcludingPort(a),
                .guid => |g| conn.guid.g == g.g,
            };
            if (matches and conn.state != .is_disconnected) {
                if (send_notification) {
                    _ = self.sendDisconnectionNotification(conn, ordering_channel, disconnect_priority);
                }
                conn.state = .is_disconnecting;
                break;
            }
        }
    }

    /// Get the connection state for a system
    pub fn getConnectionState(self: *Self, target: AddressOrGUID) ConnectionState {
        for (self.connections.items) |conn| {
            const matches = switch (target) {
                .address => |a| conn.address.equalsExcludingPort(a),
                .guid => |g| conn.guid.g == g.g,
            };
            if (matches) return conn.state;
        }
        return .is_not_connected;
    }

    /// Get my own GUID
    pub fn getMyGuid(self: *Self) RakNetGUID {
        return self.my_guid;
    }

    /// Get GUID from system address
    pub fn getGuidFromSystemAddress(self: *Self, address: SystemAddress) RakNetGUID {
        for (self.connections.items) |conn| {
            if (conn.address.equalsExcludingPort(address)) return conn.guid;
        }
        return RakNetGUID.unassigned();
    }

    /// Get system address from GUID
    pub fn getSystemAddressFromGuid(self: *Self, guid: RakNetGUID) SystemAddress {
        for (self.connections.items) |conn| {
            if (conn.guid.g == guid.g) return conn.address;
        }
        return SystemAddress.unassigned();
    }

    /// Get connections list
    pub fn getConnectionList(self: *Self, alloc: std.mem.Allocator) ![]SystemAddress {
        var list = ManagedList(SystemAddress).init(alloc);
        for (self.connections.items) |conn| {
            if (conn.state == .is_connected) {
                try list.append(conn.address);
            }
        }
        return list.toOwnedSlice();
    }

    /// Get system address by index
    pub fn getSystemAddressFromIndex(self: *Self, index: usize) ?SystemAddress {
        if (index < self.connections.items.len) {
            return self.connections.items[index].address;
        }
        return null;
    }

    // -----------------------------------------------------------------------
    // Send / Receive
    // -----------------------------------------------------------------------

    /// Send data to a system
    pub fn send(
        self: *Self,
        data: []const u8,
        priority: PacketPriority,
        reliability: PacketReliability,
        ordering_channel: u8,
        target: AddressOrGUID,
        broadcast: bool,
    ) !u32 {
        if (!self.is_active) return error.NotActive;

        const receipt = self.next_send_receipt;
        self.next_send_receipt +%= 1;

        // Build the packet
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        // Write the message ID from data[0]
        try bs.writeAlignedBytes(data);

        // Send to each matching connection
        for (self.connections.items) |*conn| {
            if (conn.state != .is_connected) continue;

            const send_to_this = if (broadcast) blk: {
                // When broadcasting, skip the specified target
                const matches = switch (target) {
                    .address => |a| conn.address.equalsExcludingPort(a),
                    .guid => |g| conn.guid.g == g.g,
                };
                break :blk !matches;
            } else blk: {
                const matches = switch (target) {
                    .address => |a| conn.address.equalsExcludingPort(a),
                    .guid => |g| conn.guid.g == g.g,
                };
                break :blk matches;
            };

            if (send_to_this) {
                try self.sendDatagram(conn, bs.getData(), priority, reliability, ordering_channel);
            }
        }

        return receipt;
    }

    /// Send via BitStream
    pub fn sendBitStream(
        self: *Self,
        stream: *const BitStream,
        priority: PacketPriority,
        reliability: PacketReliability,
        ordering_channel: u8,
        target: AddressOrGUID,
        broadcast: bool,
    ) !u32 {
        return self.send(stream.getData(), priority, reliability, ordering_channel, target, broadcast);
    }

    /// Send a loopback message to ourselves
    pub fn sendLoopback(self: *Self, data: []const u8) !void {
        const packet_data = try self.allocator.alloc(u8, data.len);
        @memcpy(packet_data, data);

        const packet = Packet{
            .system_address = SystemAddress{ .ip = .{ .ip4 = .{ .bytes = .{ 127, 0, 0, 1 }, .port = 0 } } },
            .guid = self.my_guid,
            .length = @intCast(data.len),
            .bit_size = @intCast(data.len * 8),
            .data = packet_data,
            .was_generated_locally = true,
            .allocator = self.allocator,
        };

        try self.packet_queue.append(.{ .packet = packet });
    }

    /// Receive the next packet from the queue
    pub fn receive(self: *Self) ?Packet {
        if (self.packet_queue.items.len == 0) return null;

        // Process network first
        self.updateNetwork() catch {};

        if (self.packet_queue.items.len == 0) return null;

        const entry = self.packet_queue.orderedRemove(0);
        return entry.packet;
    }

    pub fn deallocatePacket(self: *Self, packet: *const Packet) void {
        _ = self;
        // Note: data is freed but struct is on stack
        if (packet.allocator) |alloc| {
            alloc.free(packet.data);
        }
    }

    /// Push a packet back into the queue
    pub fn pushBackPacket(self: *Self, packet: Packet, push_at_head: bool) !void {
        if (push_at_head) {
            try self.packet_queue.insert(0, .{ .packet = packet });
        } else {
            try self.packet_queue.append(.{ .packet = packet });
        }
    }

    // -----------------------------------------------------------------------
    // Ping
    // -----------------------------------------------------------------------

    /// Ping a connected system
    pub fn ping(self: *Self, target: SystemAddress) !void {
        _ = self;
        _ = target;
        // Send ID_CONNECTED_PING message
    }

    /// Ping an unconnected system
    pub fn pingHost(self: *Self, host: []const u8, remote_port: u16, only_reply_if_accepting: bool) !void {
        _ = self;
        _ = host;
        _ = remote_port;
        _ = only_reply_if_accepting;
        // Send ID_UNCONNECTED_PING message
    }

    /// Get average ping for a system
    pub fn getAveragePing(self: *Self, target: AddressOrGUID) f64 {
        for (self.connections.items) |conn| {
            const matches = switch (target) {
                .address => |a| conn.address.equalsExcludingPort(a),
                .guid => |g| conn.guid.g == g.g,
            };
            if (matches) return conn.average_ping;
        }
        return -1;
    }

    /// Get last ping for a system
    pub fn getLastPing(self: *Self, target: AddressOrGUID) u32 {
        for (self.connections.items) |conn| {
            const matches = switch (target) {
                .address => |a| conn.address.equalsExcludingPort(a),
                .guid => |g| conn.guid.g == g.g,
            };
            if (matches) return conn.last_ping;
        }
        return 0;
    }

    /// Get lowest ping for a system
    pub fn getLowestPing(self: *Self, target: AddressOrGUID) u32 {
        for (self.connections.items) |conn| {
            const matches = switch (target) {
                .address => |a| conn.address.equalsExcludingPort(a),
                .guid => |g| conn.guid.g == g.g,
            };
            if (matches) return conn.lowest_ping;
        }
        return 0;
    }

    /// Set whether to ping occasionally
    pub fn setOccasionalPing(self: *Self, do_ping: bool) void {
        self.occasional_ping = do_ping;
    }

    // -----------------------------------------------------------------------
    // Offline Ping / Static Data
    // -----------------------------------------------------------------------

    /// Set data to respond with for offline ping queries
    pub fn setOfflinePingResponse(self: *Self, data: []const u8) !void {
        if (self.offline_ping_data) |old| {
            self.allocator.free(old);
        }
        const copy = try self.allocator.alloc(u8, data.len);
        @memcpy(copy, data);
        self.offline_ping_data = copy;
    }

    /// Get the offline ping response data
    pub fn getOfflinePingResponse(self: *Self) ?[]const u8 {
        return self.offline_ping_data;
    }

    // -----------------------------------------------------------------------
    // Statistics
    // -----------------------------------------------------------------------

    /// Get statistics for a system
    pub fn getStatistics(self: *Self, target: SystemAddress) ?types.RakNetStatistics {
        for (self.connections.items) |conn| {
            if (conn.address.equalsExcludingPort(target)) {
                return .{
                    .average_ping = conn.average_ping,
                    .last_ping = conn.last_ping,
                    .lowest_ping = conn.lowest_ping,
                    .mtu_size = conn.mtu_size,
                };
            }
        }
        return null;
    }

    /// Get receive buffer size
    pub fn getReceiveBufferSize(self: *Self) u32 {
        return @intCast(self.packet_queue.items.len);
    }

    // -----------------------------------------------------------------------
    // Internal network processing
    // -----------------------------------------------------------------------

    /// Update network - process incoming data
    fn updateNetwork(self: *Self) !void {
        if (!self.is_active) return;

        // Check for incoming packets on all sockets
        for (self.sockets.items) |*sock| {
            while (true) {
                const result = sock.recvFromTimeout(self.io, &self.recv_buffer, 0) catch break;
                if (result.bytes_read == 0) break;

                // Process the received packet
                try self.processIncomingPacket(
                    result.from,
                    self.recv_buffer[0..result.bytes_read],
                );
            }
        }

        // Handle timeouts
        const now: TimeMS = getTimeMs(self.io);
        for (self.connections.items) |*conn| {
            if (conn.state == .is_connected or conn.state == .is_connecting) {
                if (now - conn.connect_time > conn.timeout_time) {
                    conn.state = .is_disconnected;
                    try self.enqueueSystemPacket(
                        conn,
                        @intFromEnum(message_ids.DefaultMessageId.connection_lost),
                    );
                }
            }
            // Clean up fully disconnected entries
            if (conn.state == .is_disconnected) {
                const elapsed = now - conn.connect_time;
                if (elapsed > 5000) { // 5 second grace period
                    conn.state = .is_not_connected;
                }
            }
        }
    }

    /// Process a raw incoming packet
    fn processIncomingPacket(self: *Self, from: SystemAddress, data: []const u8) !void {
        if (data.len == 0) return;

        const msg_id: MessageId = data[0];

        switch (msg_id) {
            @intFromEnum(message_ids.DefaultMessageId.open_connection_request_1) => {
                try self.handleOpenConnectionRequest1(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.open_connection_reply_1) => {
                try self.handleOpenConnectionReply1(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.open_connection_request_2) => {
                try self.handleOpenConnectionRequest2(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.open_connection_reply_2) => {
                try self.handleOpenConnectionReply2(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.connection_request) => {
                try self.handleConnectionRequest(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.connection_request_accepted) => {
                try self.handleConnectionRequestAccepted(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.new_incoming_connection) => {
                try self.handleNewIncomingConnection(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.disconnection_notification) => {
                try self.handleDisconnection(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.connection_lost) => {
                try self.handleConnectionLost(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.connected_ping),
            @intFromEnum(message_ids.DefaultMessageId.connected_pong),
            => {
                try self.handlePingPong(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.unconnected_ping),
            @intFromEnum(message_ids.DefaultMessageId.unconnected_ping_open_connections),
            => {
                try self.handleUnconnectedPing(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.unconnected_pong) => {
                try self.handleUnconnectedPong(from, data);
            },
            @intFromEnum(message_ids.DefaultMessageId.advertise_system) => {
                try self.handleAdvertiseSystem(from, data);
            },
            else => {
                // User packet - find the connection and enqueue
                try self.enqueueUserPacket(from, data);
            },
        }
    }

    // --- Connection handshake handlers ---

    fn handleOpenConnectionRequest1(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;

        // Check ban list
        // Check if accepting connections
        if (self.max_incoming_connections == 0) return;

        // Send open_connection_reply_1 with our GUID and MTU
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.open_connection_reply_1));
        try bs.writeBytes(&message_ids.offline_message_data_id);
        try bs.writeU64(self.my_guid.g);
        try bs.writeBool(false); // hasSecurity = false
        try bs.writeU16(@intCast(types.default_mtu_size));

        // Send via the first socket
        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &from, bs.getData()) catch {};
        }
    }

    fn handleOpenConnectionReply1(self: *Self, from: SystemAddress, data: []const u8) !void {
        // Find matching connection attempt
        const conn_idx = self.findConnectionByAddress(from) orelse return;
        var conn = &self.connections.items[conn_idx];

        // Parse the response: extract GUID, MTU
        if (data.len < 28) return;

        // Send open_connection_request_2
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.open_connection_request_2));
        try bs.writeBytes(&message_ids.offline_message_data_id);
        try bs.writeU16(@intCast(types.default_mtu_size));
        try bs.writeU64(self.my_guid.g);

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &conn.address, bs.getData()) catch {};
        }

        conn.state = .is_connecting;
        conn.connect_time = getTimeMs(self.io);
    }

    fn handleOpenConnectionRequest2(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;

        // Accept the connection
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.open_connection_reply_2));
        try bs.writeBytes(&message_ids.offline_message_data_id);
        try bs.writeU64(self.my_guid.g);
        try bs.writeU16(@intCast(types.default_mtu_size));
        try bs.writeBool(false); // doSecurity

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &from, bs.getData()) catch {};
        }

        // Create connection
        const conn = Connection{
            .address = from,
            .guid = RakNetGUID.unassigned(),
            .state = .is_connected,
            .connect_time = getTimeMs(self.io),
            .connection_attempts = 0,
            .last_attempt_time = 0,
            .system_index = @intCast(self.connections.items.len),
            .timeout_time = self.default_timeout_time,
            .average_ping = 0,
            .last_ping = 0,
            .lowest_ping = 0,
            .mtu_size = types.default_mtu_size,
            .we_initiated = false,
            .password = null,
        };

        try self.connections.append(conn);
        try self.enqueueSystemPacket(
            &self.connections.items[self.connections.items.len - 1],
            @intFromEnum(message_ids.DefaultMessageId.new_incoming_connection),
        );
    }

    fn handleOpenConnectionReply2(self: *Self, from: SystemAddress, data: []const u8) !void {
        const conn_idx = self.findConnectionByAddress(from) orelse return;
        var conn = &self.connections.items[conn_idx];

        // Extract GUID and MTU from response
        if (data.len >= 28) {
            var bs = BitStream.initFromData(data);
            _ = bs.readU8() catch return; // message id
            _ = bs.readBytesAlloc(self.allocator) catch return;
            conn.guid.g = bs.readU64() catch return;
            conn.mtu_size = bs.readU16() catch return;
        }

        // Send connection_request
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.connection_request));
        try bs.writeU64(self.my_guid.g);
        try bs.writeU64(getTimeMs(self.io));
        try bs.writeBool(false); // hasSecurity

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &conn.address, bs.getData()) catch {};
        }

        conn.state = .is_connected;
        try self.enqueueSystemPacket(conn, @intFromEnum(message_ids.DefaultMessageId.connection_request_accepted));
    }

    fn handleConnectionRequest(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;
        // Accept the connection - send connection_request_accepted
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.connection_request_accepted));
        try bs.writeU64(from.ip.getPort());

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &from, bs.getData()) catch {};
        }
    }

    fn handleConnectionRequestAccepted(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;
        const conn_idx = self.findConnectionByAddress(from) orelse return;
        var conn = &self.connections.items[conn_idx];

        conn.state = .is_connected;
        try self.enqueueSystemPacket(conn, @intFromEnum(message_ids.DefaultMessageId.connection_request_accepted));
    }

    fn handleNewIncomingConnection(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;
        _ = from;
        _ = self;
        // Already handled in handleOpenConnectionRequest2
    }

    fn handleDisconnection(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;
        const conn_idx = self.findConnectionByAddress(from) orelse return;
        self.connections.items[conn_idx].state = .is_disconnected;
        try self.enqueueSystemPacket(
            &self.connections.items[conn_idx],
            @intFromEnum(message_ids.DefaultMessageId.disconnection_notification),
        );
    }

    fn handleConnectionLost(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;
        const conn_idx = self.findConnectionByAddress(from) orelse return;
        self.connections.items[conn_idx].state = .is_disconnected;
        try self.enqueueSystemPacket(
            &self.connections.items[conn_idx],
            @intFromEnum(message_ids.DefaultMessageId.connection_lost),
        );
    }

    fn handlePingPong(self: *Self, from: SystemAddress, data: []const u8) !void {
        const conn_idx = self.findConnectionByAddress(from) orelse return;
        const conn = &self.connections.items[conn_idx];

        if (data[0] == @intFromEnum(message_ids.DefaultMessageId.connected_ping)) {
            // Respond with pong
            var bs = BitStream.init(self.allocator);
            defer bs.deinit();
            try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.connected_pong));
            try bs.writeU64(getTimeMs(self.io));

            if (self.sockets.items.len > 0) {
                self.sockets.items[0].sendTo(self.io, &conn.address, bs.getData()) catch {};
            }
        }

        // Update ping times (simplified)
        if (data.len >= 9) {
            const now: TimeMS = getTimeMs(self.io);
            var bs2 = BitStream.initFromData(data[1..]);
            const send_time = bs2.readU64() catch return;
            const rtt = now -| send_time;
            if (conn.average_ping < 0) {
                // First ping
            }
            _ = rtt;
        }
    }

    fn handleUnconnectedPing(self: *Self, from: SystemAddress, data: []const u8) !void {
        _ = data;
        // Respond with unconnected pong + offline ping data
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.unconnected_pong));
        try bs.writeU64(getTimeMs(self.io));
        try bs.writeU64(self.my_guid.g);

        // Send server name/advertisement
        const server_name = "MCPE;ZigRakNet;1.0;0.0;0";
        try bs.writeU16(@intCast(server_name.len));
        try bs.writeAlignedBytes(server_name);

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &from, bs.getData()) catch {};
        }
    }

    fn handleUnconnectedPong(self: *Self, from: SystemAddress, data: []const u8) !void {
        // Forward to the user as an unconnected pong packet
        try self.enqueueUserPacket(from, data);
    }

    fn handleAdvertiseSystem(self: *Self, from: SystemAddress, data: []const u8) !void {
        try self.enqueueUserPacket(from, data);
    }

    // --- Packet queue helpers ---

    fn enqueueSystemPacket(self: *Self, conn: *const Connection, msg_id: u8) !void {
        const packet_data = try self.allocator.alloc(u8, 1);
        packet_data[0] = msg_id;

        const packet = Packet{
            .system_address = conn.address,
            .guid = conn.guid,
            .length = 1,
            .bit_size = 8,
            .data = packet_data,
            .was_generated_locally = true,
            .allocator = self.allocator,
        };

        try self.packet_queue.append(.{ .packet = packet });
    }

    fn enqueueUserPacket(self: *Self, from: SystemAddress, data: []const u8) !void {
        const packet_data = try self.allocator.alloc(u8, data.len);
        @memcpy(packet_data, data);

        // Find the GUID for this address
        var guid = RakNetGUID.unassigned();
        for (self.connections.items) |conn| {
            if (conn.address.equalsExcludingPort(from)) {
                guid = conn.guid;
                break;
            }
        }

        const packet = Packet{
            .system_address = from,
            .guid = guid,
            .length = @intCast(data.len),
            .bit_size = @intCast(data.len * 8),
            .data = packet_data,
            .was_generated_locally = false,
            .allocator = self.allocator,
        };

        try self.packet_queue.append(.{ .packet = packet });
    }

    // --- Internal helpers ---

    fn findConnectionByAddress(self: *Self, addr: SystemAddress) ?usize {
        for (self.connections.items, 0..) |conn, i| {
            if (conn.address.equalsExcludingPort(addr) and
                conn.address.getPort() == addr.getPort() and
                conn.state != .is_not_connected)
            {
                return i;
            }
        }
        return null;
    }

    fn sendDatagram(
        self: *Self,
        conn: *Connection,
        data: []const u8,
        priority: PacketPriority,
        reliability: PacketReliability,
        ordering_channel: u8,
    ) !void {
        _ = priority;
        _ = reliability;
        _ = ordering_channel;

        // Simple: just send the data directly for now
        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &conn.address, data) catch {};
        }
    }

    fn sendOpenConnectionRequest1(self: *Self, dest: SystemAddress, send_attempts: u32, interval_ms: u32) !void {
        _ = send_attempts;
        _ = interval_ms;

        // Build open connection request 1
        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.open_connection_request_1));
        try bs.writeBytes(&message_ids.offline_message_data_id);
        try bs.writeU8(message_ids.protocol_version);

        // Pad to MTU size
        try bs.padWithZeroToByteLength(types.default_mtu_size);

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &dest, bs.getData()) catch {};
        }
    }

    fn sendDisconnectionNotification(
        self: *Self,
        conn: *Connection,
        channel: u8,
        priority: PacketPriority,
    ) !void {
        _ = channel;
        _ = priority;

        var bs = BitStream.init(self.allocator);
        defer bs.deinit();

        try bs.writeU8(@intFromEnum(message_ids.DefaultMessageId.disconnection_notification));

        if (self.sockets.items.len > 0) {
            self.sockets.items[0].sendTo(self.io, &conn.address, bs.getData()) catch {};
        }
    }

    /// Resolve a hostname to an IP address
    fn resolveHostname(self: *Self, host: []const u8, port: u16) !net.IpAddress {
        _ = self;

        // Try direct IP parse first
        if (net.IpAddress.parse(host, port)) |ip| return ip else |_| {}

        // DNS resolution - for now, return error
        return error.CannotResolveDomainName;
    }
};

// -----------------------------------------------------------------------
// Time helper - get current monotonic time in milliseconds
// -----------------------------------------------------------------------

fn getTimeMs(ioc: io) types.TimeMS {
    const ts = ioc.vtable.now(ioc.userdata, .awake);
    return @intCast(ts.toMilliseconds());
}

// -----------------------------------------------------------------------
// IP pattern matching (supports * wildcards)
// -----------------------------------------------------------------------

fn matchIPPattern(ip: []const u8, pattern: []const u8) bool {
    if (std.mem.eql(u8, pattern, "*")) return true;
    if (std.mem.eql(u8, ip, pattern)) return true;

    // Simple wildcard matching
    var ip_idx: usize = 0;
    var pat_idx: usize = 0;
    var star_idx: ?usize = null;
    var match_idx: usize = 0;

    while (ip_idx < ip.len) {
        if (pat_idx < pattern.len and (pattern[pat_idx] == '?' or
            (pattern[pat_idx] != '*' and ip[ip_idx] == pattern[pat_idx])))
        {
            ip_idx += 1;
            pat_idx += 1;
        } else if (pat_idx < pattern.len and pattern[pat_idx] == '*') {
            star_idx = pat_idx;
            match_idx = ip_idx;
            pat_idx += 1;
        } else if (star_idx != null) {
            pat_idx = star_idx.? + 1;
            match_idx += 1;
            ip_idx = match_idx;
        } else {
            return false;
        }
    }

    while (pat_idx < pattern.len and pattern[pat_idx] == '*') {
        pat_idx += 1;
    }

    return pat_idx == pattern.len;
}

test "IP pattern matching" {
    try std.testing.expect(matchIPPattern("192.168.1.1", "192.168.1.1"));
    try std.testing.expect(matchIPPattern("192.168.1.1", "*"));
    try std.testing.expect(matchIPPattern("192.168.1.1", "192.168.*"));
    try std.testing.expect(matchIPPattern("192.168.1.1", "192.*.1.1"));
    try std.testing.expect(!matchIPPattern("192.168.1.1", "10.0.0.*"));
}
