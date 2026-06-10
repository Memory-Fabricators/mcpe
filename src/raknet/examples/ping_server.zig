//! Simple ping server example using zig-raknet.
//!
//! Listens on port 19132 and responds to pings.
//! Run with: zig build run-server

const std = @import("std");
const io = std.Io;
const raknet = @import("zig-raknet");

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create and configure the peer
    var peer = raknet.RakPeer.init(allocator, init.io);
    defer peer.deinit();

    const port: u16 = 19132;
    std.debug.print("Starting RakNet ping server on port {d}...\n", .{port});

    _ = try peer.startup(.{
        .max_connections = 32,
        .sockets = &.{
            .{ .port = port },
        },
    });
    peer.setMaximumIncomingConnections(32);

    // Set offline ping response (MCPE-style server info)
    try peer.setOfflinePingResponse("MCPE;ZigRakNet Server;1.0;0.0;0;32");

    std.debug.print("Server is running. Press Ctrl+C to stop.\n", .{});

    // Main loop
    while (true) {
        while (peer.receive()) |packet| {
            switch (packet.data[0]) {
                @intFromEnum(raknet.DefaultMessageId.new_incoming_connection) => {
                    std.debug.print("New connection: {}\n", .{packet.system_address});
                },
                @intFromEnum(raknet.DefaultMessageId.disconnection_notification),
                @intFromEnum(raknet.DefaultMessageId.connection_lost),
                => {
                    std.debug.print("Client disconnected: {}\n", .{packet.system_address});
                },
                @intFromEnum(raknet.DefaultMessageId.unconnected_ping),
                @intFromEnum(raknet.DefaultMessageId.unconnected_ping_open_connections),
                => {
                    std.debug.print("Ping from: {}\n", .{packet.system_address});
                },
                else => {
                    std.debug.print("Received packet 0x{X:0>2} from {}\n", .{
                        packet.data[0],
                        packet.system_address,
                    });
                },
            }
            peer.deallocatePacket(&packet);
        }

        // Small sleep to avoid busy-waiting
        try io.sleep(init.io, .{ .nanoseconds = 10 * std.time.ns_per_ms }, .awake);
    }
}
