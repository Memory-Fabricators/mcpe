//! ZigRakNet - A Zig 0.16 port of the RakNet networking library.
//!
//! RakNet is a cross-platform UDP networking library designed for games.
//! This port uses Zig's native idioms, allocator-based memory management,
//! and the new std.Io interface.
//!
//! ## Quick Start
//!
//! ```zig
//! const raknet = @import("zig-raknet");
//!
//! // Server example
//! var peer = raknet.RakPeer.init(allocator);
//! defer peer.deinit();
//!
//! try peer.startup(.{
//!     .max_connections = 32,
//!     .sockets = &.{
//!         .{ .port = 19132 },
//!     },
//! });
//! peer.setMaximumIncomingConnections(32);
//!
//! // Main loop
//! while (running) {
//!     while (peer.receive()) |packet| {
//!         defer peer.deallocatePacket(&packet);
//!         switch (packet.data[0]) {
//!             @intFromEnum(raknet.message_ids.DefaultMessageId.new_incoming_connection) => {
//!                 std.debug.print("New connection from {}\n", .{packet.system_address});
//!             },
//!             // Handle your custom packets here
//!             else => {},
//!         }
//!     }
//! }
//! ```
//!
//! ## Client example
//!
//! ```zig
//! var peer = raknet.RakPeer.init(allocator);
//! defer peer.deinit();
//!
//! try peer.startup(.{
//!     .max_connections = 1,
//!     .sockets = &.{.{}}, // auto-assign port
//! });
//!
//! _ = try peer.connect("127.0.0.1", 19132, null, 12, 500, 0);
//!
//! while (running) {
//!     while (peer.receive()) |packet| {
//!         defer peer.deallocatePacket(&packet);
//!         switch (packet.data[0]) {
//!             @intFromEnum(raknet.message_ids.DefaultMessageId.connection_request_accepted) => {
//!                 std.debug.print("Connected!\n", .{});
//!             },
//!             else => {},
//!         }
//!     }
//! }
//! ```

pub const types = @import("types.zig");
pub const message_ids = @import("message_ids.zig");
pub const bitstream = @import("bitstream.zig");
pub const socket = @import("socket.zig");
pub const peer = @import("peer.zig");

pub const RakPeer = peer.RakPeer;
pub const Config = peer.Config;
pub const BitStream = bitstream.BitStream;
pub const SystemAddress = types.SystemAddress;
pub const RakNetGUID = types.RakNetGUID;
pub const Packet = types.Packet;
pub const PacketPriority = types.PacketPriority;
pub const PacketReliability = types.PacketReliability;
pub const SocketDescriptor = types.SocketDescriptor;
pub const ConnectionState = types.ConnectionState;
pub const StartupResult = types.StartupResult;
pub const ConnectionAttemptResult = types.ConnectionAttemptResult;
pub const DefaultMessageId = message_ids.DefaultMessageId;
pub const MessageId = message_ids.MessageId;

test {
    _ = types;
    _ = message_ids;
    _ = bitstream;
    _ = socket;
    _ = peer;
}
