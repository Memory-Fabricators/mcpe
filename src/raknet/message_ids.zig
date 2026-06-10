//! All the message identifiers used by RakNet.
//! Message identifiers comprise the first byte of any message.
//!
//! Ported from MessageIdentifiers.h

/// First byte of a network message
pub const MessageId = u8;

/// Out-of-band identifiers (used for NAT traversal etc.)
pub const OutOfBandId = enum(u8) {
    nat_establish_unidirectional,
    nat_establish_bidirectional,
    nat_type_detect,
    router2_reply_to_sender_port,
    router2_reply_to_specified_port,
    router2_mini_punch_reply,
    router2_mini_punch_reply_bounce,
    xbox360_voice,
    xbox360_get_network_room,
    xbox360_return_network_room,
};

/// Default message identifiers used by RakNet.
/// User packets should start at `user_packet_enum`.
pub const DefaultMessageId = enum(u8) {
    // --- Reserved internal types ---
    /// Ping from a connected system. Update timestamps (internal use only)
    connected_ping,
    /// Ping from an unconnected system. Reply but do not update timestamps.
    unconnected_ping,
    /// Ping from an unconnected system. Only reply if we have open connections.
    unconnected_ping_open_connections,
    /// Pong from a connected system. Update timestamps (internal use only)
    connected_pong,
    /// A reliable packet to detect lost connections (internal use only)
    detect_lost_connections,
    /// C2S: Initial query
    open_connection_request_1,
    /// S2C: Response to open_connection_request_1
    open_connection_reply_1,
    /// C2S: Second connection request
    open_connection_request_2,
    /// S2C: Response to open_connection_request_2
    open_connection_reply_2,
    /// C2S: Connection request
    connection_request,
    /// Remote system requires secure connections
    remote_system_requires_public_key,
    /// We passed a public key but the other system didn't have security
    our_system_requires_security,
    /// Wrong public key
    public_key_mismatch,
    /// Out of band internal
    out_of_band_internal,
    /// Send receipt acked
    snd_receipt_acked,
    /// Send receipt lost
    snd_receipt_loss,

    // --- User types ---
    /// Connection request accepted
    connection_request_accepted,
    /// Connection attempt failed
    connection_attempt_failed,
    /// Already connected
    already_connected,
    /// New incoming connection
    new_incoming_connection,
    /// No free incoming connections
    no_free_incoming_connections,
    /// Disconnection notification
    disconnection_notification,
    /// Connection lost
    connection_lost,
    /// Connection banned
    connection_banned,
    /// Invalid password
    invalid_password,
    /// Incompatible protocol version
    incompatible_protocol_version,
    /// IP recently connected
    ip_recently_connected,
    /// Timestamp
    timestamp,
    /// Unconnected pong
    unconnected_pong,
    /// Advertise system
    advertise_system,
    /// Download progress
    download_progress,

    // --- ConnectionGraph2 plugin ---
    remote_disconnection_notification,
    remote_connection_lost,
    remote_new_incoming_connection,

    // --- FileListTransfer plugin ---
    file_list_transfer_header,
    file_list_transfer_file,
    file_list_reference_push_ack,

    // --- DirectoryDeltaTransfer plugin ---
    ddt_download_request,

    // --- RakNetTransport plugin ---
    transport_string,

    // --- ReplicaManager plugin ---
    replica_manager_construction,
    replica_manager_scope_change,
    replica_manager_serialize,
    replica_manager_download_started,
    replica_manager_download_complete,

    // --- RakVoice plugin ---
    rakvoice_open_channel_request,
    rakvoice_open_channel_reply,
    rakvoice_close_channel,
    rakvoice_data,

    // --- Autopatcher plugin ---
    autopatcher_get_changelist_since_date,
    autopatcher_creation_list,
    autopatcher_deletion_list,
    autopatcher_get_patch,
    autopatcher_patch_list,
    autopatcher_repository_fatal_error,
    autopatcher_finished_internal,
    autopatcher_finished,
    autopatcher_restart_application,

    // --- NATPunchthrough plugin ---
    nat_punchthrough_request,
    nat_group_punchthrough_request,
    nat_group_punchthrough_reply,
    nat_connect_at_time,
    nat_get_most_recent_port,
    nat_client_ready,
    nat_group_punchthrough_failure_notification,
    nat_target_not_connected,
    nat_target_unresponsive,
    nat_connection_to_target_lost,
    nat_already_in_progress,
    nat_punchthrough_failed,
    nat_punchthrough_succeeded,
    nat_group_punch_failed,
    nat_group_punch_succeeded,

    // --- ReadyEvent plugin ---
    ready_event_set,
    ready_event_unset,
    ready_event_all_set,
    ready_event_query,

    // --- Lobby ---
    lobby_general,

    // --- RPC ---
    rpc_remote_error,
    rpc_plugin,

    // --- More FileListTransfer ---
    file_list_reference_push,
    ready_event_force_all_set,

    // --- Rooms ---
    rooms_execute_func,
    rooms_logon_status,
    rooms_handle_change,

    // --- Lobby2 ---
    lobby2_send_message,
    lobby2_server_error,

    // --- FullyConnectedMesh2 plugin ---
    fcm2_new_host,
    fcm2_request_fcmguid,
    fcm2_respond_connection_count,
    fcm2_inform_fcmguid,
    fcm2_update_min_total_connection_count,

    // --- UDP proxy ---
    udp_proxy_general,

    // --- SQLite3Plugin ---
    sqlite3_exec,
    sqlite3_unknown_db,
    sqllite_logger,

    // --- NAT type detection ---
    nat_type_detection_request,
    nat_type_detection_result,

    // --- Router2 plugin ---
    router2_internal,
    router2_forwarding_no_path,
    router2_forwarding_established,
    router2_rerouted,

    // --- Team balancer plugin ---
    team_balancer_internal,
    team_balancer_requested_team_change_pending,
    team_balancer_teams_locked,
    team_balancer_team_assigned,

    // --- Lightspeed ---
    lightspeed_integration,

    // --- Xbox lobby ---
    xbox_lobby,

    // --- Two-way authentication ---
    two_way_authentication_incoming_challenge_success,
    two_way_authentication_outgoing_challenge_success,
    two_way_authentication_incoming_challenge_failure,
    two_way_authentication_outgoing_challenge_failure,
    two_way_authentication_outgoing_challenge_timeout,
    two_way_authentication_negotiation,

    // --- Cloud ---
    cloud_post_request,
    cloud_release_request,
    cloud_get_request,
    cloud_get_response,
    cloud_unsubscribe_request,
    cloud_server_to_server_command,
    cloud_subscription_notification,

    // --- Reserved ---
    reserved_1,
    reserved_2,
    reserved_3,
    reserved_4,
    reserved_5,
    reserved_6,
    reserved_7,
    reserved_8,
    reserved_9,

    /// Start your custom packet IDs here.
    user_packet_enum,

    _,
};

/// RAKNET_PROTOCOL_VERSION - must match between peers.
pub const protocol_version: u8 = 6;

/// The offline message ID used during connection handshake.
pub const offline_message_data_id: [16]u8 = .{
    0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe,
    0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78,
};
