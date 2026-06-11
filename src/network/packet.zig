//! Minecraft Bedrock Edition packet system - Zig port.
//!
//! Ported from src/network/Packet.h, Packet.cpp, and packet/*.h

const std = @import("std");
const raknet = @import("raknet");

const BitStream = raknet.BitStream;
const RakNetGUID = raknet.RakNetGUID;
const PacketPriority = raknet.PacketPriority;
const PacketReliability = raknet.PacketReliability;

// ---------------------------------------------------------------------------
// Packet IDs
// ---------------------------------------------------------------------------

pub const PacketId = enum(u8) {
    keepalive = 0,

    login,
    login_status,
    ready,

    message,
    set_time,

    start_game,

    add_mob,
    add_player,
    remove_player,
    teleport_entity,

    add_entity,
    remove_entity,
    add_item_entity,
    take_item_entity,

    move_entity,
    move_entity_pos,
    move_entity_rot,
    move_entity_pos_rot,
    move_player,

    place_block,
    remove_block,
    update_block,

    add_painting,

    explode,

    level_event,
    tile_event,
    entity_event,

    request_chunk,
    chunk_data,

    player_equipment,
    player_armor_equipment,
    interact,
    use_item,
    player_action,
    update_armor,
    hurt_armor,

    set_entity_data,
    set_entity_motion,
    set_health,
    set_spawn_position,

    animate,
    respawn,

    send_inventory,
    drop_item,

    container_open,
    container_close,
    container_set_slot,
    container_set_data,
    container_set_content,
    container_ack,

    chat,
    sign_update,

    adventure_settings,

    _,
};

pub const num_packets: usize = @intFromEnum(PacketId.adventure_settings) + 1;

/// Convert wire byte to PacketId (subtracting ID_USER_PACKET_ENUM offset)
pub fn fromWire(id: u8) ?PacketId {
    const raw = id -| @intFromEnum(raknet.DefaultMessageId.user_packet_enum);
    if (raw >= num_packets) return null;
    return @enumFromInt(raw);
}

/// Convert PacketId to wire byte
pub fn toWire(id: PacketId) u8 {
    return @intFromEnum(raknet.DefaultMessageId.user_packet_enum) + @intFromEnum(id);
}

// ---------------------------------------------------------------------------
// Forward declarations (packet types)
// ---------------------------------------------------------------------------

pub const LoginPacket = @import("packet/login.zig").LoginPacket;
pub const LoginStatusPacket = @import("packet/login_status.zig").LoginStatusPacket;
pub const ReadyPacket = @import("packet/ready.zig").ReadyPacket;
pub const MessagePacket = @import("packet/message.zig").MessagePacket;
pub const SetTimePacket = @import("packet/set_time.zig").SetTimePacket;
pub const StartGamePacket = @import("packet/start_game.zig").StartGamePacket;
pub const AddMobPacket = @import("packet/add_mob.zig").AddMobPacket;
pub const AddPlayerPacket = @import("packet/add_player.zig").AddPlayerPacket;
pub const RemovePlayerPacket = @import("packet/remove_player.zig").RemovePlayerPacket;
pub const AddEntityPacket = @import("packet/add_entity.zig").AddEntityPacket;
pub const RemoveEntityPacket = @import("packet/remove_entity.zig").RemoveEntityPacket;
pub const AddItemEntityPacket = @import("packet/add_item_entity.zig").AddItemEntityPacket;
pub const TakeItemEntityPacket = @import("packet/take_item_entity.zig").TakeItemEntityPacket;
pub const MoveEntityPacket = @import("packet/move_entity.zig").MoveEntityPacket;
pub const MovePlayerPacket = @import("packet/move_player.zig").MovePlayerPacket;
pub const PlaceBlockPacket = @import("packet/place_block.zig").PlaceBlockPacket;
pub const RemoveBlockPacket = @import("packet/remove_block.zig").RemoveBlockPacket;
pub const UpdateBlockPacket = @import("packet/update_block.zig").UpdateBlockPacket;
pub const AddPaintingPacket = @import("packet/add_painting.zig").AddPaintingPacket;
pub const ExplodePacket = @import("packet/explode.zig").ExplodePacket;
pub const LevelEventPacket = @import("packet/level_event.zig").LevelEventPacket;
pub const TileEventPacket = @import("packet/tile_event.zig").TileEventPacket;
pub const EntityEventPacket = @import("packet/entity_event.zig").EntityEventPacket;
pub const RequestChunkPacket = @import("packet/request_chunk.zig").RequestChunkPacket;
pub const ChunkDataPacket = @import("packet/chunk_data.zig").ChunkDataPacket;
pub const PlayerEquipmentPacket = @import("packet/player_equipment.zig").PlayerEquipmentPacket;
pub const PlayerArmorEquipmentPacket = @import("packet/player_armor_equipment.zig").PlayerArmorEquipmentPacket;
pub const InteractPacket = @import("packet/interact.zig").InteractPacket;
pub const UseItemPacket = @import("packet/use_item.zig").UseItemPacket;
pub const PlayerActionPacket = @import("packet/player_action.zig").PlayerActionPacket;
pub const HurtArmorPacket = @import("packet/hurt_armor.zig").HurtArmorPacket;
pub const SetEntityDataPacket = @import("packet/set_entity_data.zig").SetEntityDataPacket;
pub const SetEntityMotionPacket = @import("packet/set_entity_motion.zig").SetEntityMotionPacket;
pub const SetHealthPacket = @import("packet/set_health.zig").SetHealthPacket;
pub const SetSpawnPositionPacket = @import("packet/set_spawn_position.zig").SetSpawnPositionPacket;
pub const AnimatePacket = @import("packet/animate.zig").AnimatePacket;
pub const RespawnPacket = @import("packet/respawn.zig").RespawnPacket;
pub const SendInventoryPacket = @import("packet/send_inventory.zig").SendInventoryPacket;
pub const DropItemPacket = @import("packet/drop_item.zig").DropItemPacket;
pub const ContainerOpenPacket = @import("packet/container_open.zig").ContainerOpenPacket;
pub const ContainerClosePacket = @import("packet/container_close.zig").ContainerClosePacket;
pub const ContainerSetSlotPacket = @import("packet/container_set_slot.zig").ContainerSetSlotPacket;
pub const ContainerSetDataPacket = @import("packet/container_set_data.zig").ContainerSetDataPacket;
pub const ContainerSetContentPacket = @import("packet/container_set_content.zig").ContainerSetContentPacket;
pub const ContainerAckPacket = @import("packet/container_ack.zig").ContainerAckPacket;
pub const ChatPacket = @import("packet/chat.zig").ChatPacket;
pub const SignUpdatePacket = @import("packet/sign_update.zig").SignUpdatePacket;
pub const AdventureSettingsPacket = @import("packet/adventure_settings.zig").AdventureSettingsPacket;
pub const TeleportEntityPacket = @import("packet/teleport_entity.zig").TeleportEntityPacket;

// ---------------------------------------------------------------------------
// Packet utility functions
// ---------------------------------------------------------------------------

/// Rotation helpers - converts degrees to/from packed byte representation
pub const rotation = struct {
    /// Convert degrees to packed signed byte (360° → 256)
    pub fn degreesToChar(rot: f32) i8 {
        return @intFromFloat(@round(rot / 360.0 * 256.0));
    }

    /// Convert packed signed byte to degrees (256 → 360°)
    pub fn charToDegrees(rot: i8) f32 {
        return @as(f32, @floatFromInt(rot)) / 256.0 * 360.0;
    }
};

/// ItemInstance serialization helpers
pub const ItemInstance = struct {
    id: i16,
    count: u8,
    aux_value: i16,

    pub fn write(self: @This(), bs: *BitStream) !void {
        try bs.writeU16(@bitCast(self.id));
        try bs.writeU8(self.count);
        try bs.writeU16(@bitCast(self.aux_value));
    }

    pub fn read(bs: *BitStream) !@This() {
        return .{
            .id = @bitCast(try bs.readU16()),
            .count = try bs.readU8(),
            .aux_value = @bitCast(try bs.readU16()),
        };
    }
};

// ---------------------------------------------------------------------------
// Packet trait / interface
// ---------------------------------------------------------------------------

/// Every packet must support these operations.
pub fn PacketTrait(comptime T: type) type {
    return struct {
        pub const write = T.write;
        pub const read = T.read;
        pub const id = T.id;
    };
}

/// All packet types as a tagged union for dispatch
pub const PacketData = union(PacketId) {
    keepalive: void,

    login: LoginPacket,
    login_status: LoginStatusPacket,
    ready: ReadyPacket,

    message: MessagePacket,
    set_time: SetTimePacket,

    start_game: StartGamePacket,

    add_mob: AddMobPacket,
    add_player: AddPlayerPacket,
    remove_player: RemovePlayerPacket,
    teleport_entity: TeleportEntityPacket,

    add_entity: AddEntityPacket,
    remove_entity: RemoveEntityPacket,
    add_item_entity: AddItemEntityPacket,
    take_item_entity: TakeItemEntityPacket,

    move_entity: MoveEntityPacket,
    move_entity_pos: MoveEntityPacket,
    move_entity_rot: MoveEntityPacket,
    move_entity_pos_rot: MoveEntityPacket,
    move_player: MovePlayerPacket,

    place_block: PlaceBlockPacket,
    remove_block: RemoveBlockPacket,
    update_block: UpdateBlockPacket,

    add_painting: AddPaintingPacket,

    explode: ExplodePacket,

    level_event: LevelEventPacket,
    tile_event: TileEventPacket,
    entity_event: EntityEventPacket,

    request_chunk: RequestChunkPacket,
    chunk_data: ChunkDataPacket,

    player_equipment: PlayerEquipmentPacket,
    player_armor_equipment: PlayerArmorEquipmentPacket,
    interact: InteractPacket,
    use_item: UseItemPacket,
    player_action: PlayerActionPacket,
    update_armor: HurtArmorPacket,
    hurt_armor: HurtArmorPacket,

    set_entity_data: SetEntityDataPacket,
    set_entity_motion: SetEntityMotionPacket,
    set_health: SetHealthPacket,
    set_spawn_position: SetSpawnPositionPacket,

    animate: AnimatePacket,
    respawn: RespawnPacket,

    send_inventory: SendInventoryPacket,
    drop_item: DropItemPacket,

    container_open: ContainerOpenPacket,
    container_close: ContainerClosePacket,
    container_set_slot: ContainerSetSlotPacket,
    container_set_data: ContainerSetDataPacket,
    container_set_content: ContainerSetContentPacket,
    container_ack: ContainerAckPacket,

    chat: ChatPacket,
    sign_update: SignUpdatePacket,

    adventure_settings: AdventureSettingsPacket,

    _: void,

    /// Serialize this packet to a BitStream
    pub fn write(self: PacketData, bs: *BitStream) !void {
        switch (self) {
            inline else => |*payload| {
                // Write the message ID header
                try bs.writeU8(toWire(@as(PacketId, self)));
                // Delegate to the specific packet's write method
                if (comptime std.meta.hasFn(@TypeOf(payload.*), "write")) {
                    try payload.write(bs);
                }
            },
        }
    }

    /// Deserialize from a BitStream (message ID already consumed)
    pub fn read(comptime packet_id: PacketId, bs: *BitStream, allocator: std.mem.Allocator) !PacketData {
        return switch (packet_id) {
            .keepalive => .{ .keepalive = {} },
            inline else => |tag| {
                const T = std.meta.TagPayload(@TypeOf(PacketData), tag);
                if (comptime std.meta.hasFn(T, "read")) {
                    const payload = try T.read(bs, allocator);
                    return @unionInit(PacketData, @tagName(tag), payload);
                } else {
                    return @unionInit(PacketData, @tagName(tag), .{});
                }
            },
        };
    }

    /// Free any allocated resources
    pub fn deinit(self: *PacketData, allocator: std.mem.Allocator) void {
        switch (self.*) {
            inline else => |*payload| {
                if (comptime std.meta.hasFn(@TypeOf(payload.*), "deinit")) {
                    payload.deinit(allocator);
                }
            },
        }
    }

    /// Get the packet ID
    pub fn id(self: PacketData) PacketId {
        return @as(PacketId, self);
    }
};

/// Wraps a packet with routing metadata
pub const Packet = struct {
    data: PacketData,
    priority: PacketPriority = .high_priority,
    reliability: PacketReliability = .reliable,

    pub fn init(data: PacketData) Packet {
        return .{ .data = data };
    }

    pub fn write(self: *const Packet, bs: *BitStream) !void {
        try self.data.write(bs);
    }

    pub fn deinit(self: *Packet, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
    }
};

// ---------------------------------------------------------------------------
// NetEventCallback - handler interface for packets
// ---------------------------------------------------------------------------

/// Callback interface for handling network events.
/// Use this as a mixin: embed in your handler struct and override methods.
pub const NetEventCallback = struct {
    /// Called when connected to host
    onConnect: ?*const fn (ctx: *anyopaque, host_guid: RakNetGUID) void = null,
    /// Called when unable to connect
    onUnableToConnect: ?*const fn (ctx: *anyopaque) void = null,
    /// Called when a new client connects (server-side)
    onNewClient: ?*const fn (ctx: *anyopaque, client_guid: RakNetGUID) void = null,
    /// Called on disconnect
    onDisconnect: ?*const fn (ctx: *anyopaque, guid: RakNetGUID) void = null,

    /// Default handler for unhandled packets
    handleDefault: ?*const fn (ctx: *anyopaque, source: RakNetGUID, data: *PacketData) void = null,

    /// Per-packet handlers (populated dynamically or set explicitly)
    handlers: [num_packets]?*const fn (ctx: *anyopaque, source: RakNetGUID, data: *PacketData) void = @splat(null),

    /// Dispatch a packet to the appropriate handler
    pub fn dispatch(self: *NetEventCallback, ctx: *anyopaque, source: RakNetGUID, packet: *PacketData) void {
        const idx = @intFromEnum(packet.id());
        if (idx < num_packets) {
            if (self.handlers[idx]) |handler| {
                handler(ctx, source, packet);
                return;
            }
        }
        if (self.handleDefault) |h| {
            h(ctx, source, packet);
        }
    }
};

// ---------------------------------------------------------------------------
// Packet factory - create packets from wire data
// ---------------------------------------------------------------------------

/// Deserialize a packet from raw data received over the network
pub fn deserialize(data: []const u8, allocator: std.mem.Allocator) !?Packet {
    if (data.len == 0) return null;

    const wire_id = data[0];
    const packet_id = fromWire(wire_id) orelse return null;

    var bs = BitStream.initFromData(data[1..]);
    const packet_data = try PacketData.read(packet_id, &bs, allocator);
    return Packet.init(packet_data);
}
