//! NBT (Named Binary Tag) - Minecraft's structured binary format.
//! Ported from nbt/Tag.h, Tag.cpp, and all tag types.
//!
//! Uses a tagged union pattern for memory safety (no virtual dispatch).

const std = @import("std");
const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Tag type identifiers
// ---------------------------------------------------------------------------

pub const TagType = enum(u8) {
    end = 0,
    byte = 1,
    short = 2,
    int = 3,
    long = 4,
    float = 5,
    double = 6,
    byte_array = 7,
    string = 8,
    list = 9,
    compound = 10,
    _,
};

pub fn tagTypeName(t: TagType) []const u8 {
    return switch (t) {
        .end => "TAG_End",
        .byte => "TAG_Byte",
        .short => "TAG_Short",
        .int => "TAG_Int",
        .long => "TAG_Long",
        .float => "TAG_Float",
        .double => "TAG_Double",
        .byte_array => "TAG_Byte_Array",
        .string => "TAG_String",
        .list => "TAG_List",
        .compound => "TAG_Compound",
        _ => "UNKNOWN",
    };
}

// ---------------------------------------------------------------------------
// Tag - tagged union of all NBT types
// ---------------------------------------------------------------------------

pub const Tag = union(TagType) {
    end: void,
    byte: ByteTag,
    short: ShortTag,
    int: IntTag,
    long: LongTag,
    float: FloatTag,
    double: DoubleTag,
    byte_array: ByteArrayTag,
    string: StringTag,
    list: ListTag,
    compound: CompoundTag,

    pub fn deinit(self: *Tag, allocator: Allocator) void {
        switch (self.*) {
            .end => {},
            .byte => |*t| t.deinit(allocator),
            .short => |*t| t.deinit(allocator),
            .int => |*t| t.deinit(allocator),
            .long => |*t| t.deinit(allocator),
            .float => |*t| t.deinit(allocator),
            .double => |*t| t.deinit(allocator),
            .byte_array => |*t| t.deinit(allocator),
            .string => |*t| t.deinit(allocator),
            .list => |*t| t.deinit(allocator),
            .compound => |*t| t.deinit(allocator),
        }
    }

    pub fn getName(self: *const Tag) []const u8 {
        return switch (self.*) {
            .end => "",
            inline else => |*t| t.name,
        };
    }

    pub fn getType(self: Tag) TagType {
        return @as(TagType, self);
    }

    pub fn copy(self: *const Tag, allocator: Allocator) !Tag {
        return switch (self.*) {
            .end => .end,
            inline else => |*t| t.copy(allocator),
        };
    }

    pub fn format(
        self: Tag,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .end => try writer.writeAll("TAG_End"),
            .byte => |t| try writer.print("TAG_Byte(\"{s}\"): {d}", .{ t.name, t.data }),
            .short => |t| try writer.print("TAG_Short(\"{s}\"): {d}", .{ t.name, t.data }),
            .int => |t| try writer.print("TAG_Int(\"{s}\"): {d}", .{ t.name, t.data }),
            .long => |t| try writer.print("TAG_Long(\"{s}\"): {d}", .{ t.name, t.data }),
            .float => |t| try writer.print("TAG_Float(\"{s}\"): {d}", .{ t.name, t.data }),
            .double => |t| try writer.print("TAG_Double(\"{s}\"): {d}", .{ t.name, t.data }),
            .byte_array => |t| try writer.print("TAG_Byte_Array(\"{s}\"): [{d} bytes]", .{ t.name, t.data.len }),
            .string => |t| try writer.print("TAG_String(\"{s}\"): {s}", .{ t.name, t.data }),
            .list => |t| try writer.print("TAG_List(\"{s}\"): {d} entries", .{ t.name, t.items.len }),
            .compound => |t| try writer.print("TAG_Compound(\"{s}\"): {d} entries", .{ t.name, t.map.count() }),
        }
    }
};

// ---------------------------------------------------------------------------
// Primitive tag types
// ---------------------------------------------------------------------------

pub const ByteTag = struct {
    name: []const u8,
    data: i8,

    pub fn init(name: []const u8, data: i8) ByteTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *ByteTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const ByteTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .byte = .{ .name = self.name, .data = self.data } };
    }
};

pub const ShortTag = struct {
    name: []const u8,
    data: i16,

    pub fn init(name: []const u8, data: i16) ShortTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *ShortTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const ShortTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .short = .{ .name = self.name, .data = self.data } };
    }
};

pub const IntTag = struct {
    name: []const u8,
    data: i32,

    pub fn init(name: []const u8, data: i32) IntTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *IntTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const IntTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .int = .{ .name = self.name, .data = self.data } };
    }
};

pub const LongTag = struct {
    name: []const u8,
    data: i64,

    pub fn init(name: []const u8, data: i64) LongTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *LongTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const LongTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .long = .{ .name = self.name, .data = self.data } };
    }
};

pub const FloatTag = struct {
    name: []const u8,
    data: f32,

    pub fn init(name: []const u8, data: f32) FloatTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *FloatTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const FloatTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .float = .{ .name = self.name, .data = self.data } };
    }
};

pub const DoubleTag = struct {
    name: []const u8,
    data: f64,

    pub fn init(name: []const u8, data: f64) DoubleTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *DoubleTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const DoubleTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .double = .{ .name = self.name, .data = self.data } };
    }
};

pub const StringTag = struct {
    name: []const u8,
    data: []const u8,

    pub fn init(name: []const u8, data: []const u8) StringTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *StringTag, allocator: Allocator) void {
        _ = allocator;
        _ = self;
    }

    pub fn copy(self: *const StringTag, allocator: Allocator) !Tag {
        _ = allocator;
        return .{ .string = .{ .name = self.name, .data = self.data } };
    }
};

pub const ByteArrayTag = struct {
    name: []const u8,
    data: []u8,

    pub fn init(name: []const u8, data: []u8) ByteArrayTag {
        return .{ .name = name, .data = data };
    }

    pub fn deinit(self: *ByteArrayTag, allocator: Allocator) void {
        allocator.free(self.data);
        self.data = &.{};
    }

    pub fn copy(self: *const ByteArrayTag, allocator: Allocator) !Tag {
        const data = try allocator.dupe(u8, self.data);
        return .{ .byte_array = .{ .name = self.name, .data = data } };
    }
};

// ---------------------------------------------------------------------------
// List tag - ordered list of same-type tags
// ---------------------------------------------------------------------------

pub const ListTag = struct {
    name: []const u8,
    items: std.ArrayList(Tag),
    item_type: TagType = .end,

    pub fn init(allocator: Allocator, name: []const u8) ListTag {
        return .{
            .name = name,
            .items = std.ArrayList(Tag).init(allocator),
        };
    }

    pub fn deinit(self: *ListTag, allocator: Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit();
    }

    pub fn add(self: *ListTag, tag: Tag) !void {
        if (self.items.items.len == 0) {
            self.item_type = tag.getType();
        }
        try self.items.append(tag);
    }

    pub fn get(self: *const ListTag, index: usize) ?*const Tag {
        if (index >= self.items.items.len) return null;
        return &self.items.items[index];
    }

    pub fn len(self: *const ListTag) usize {
        return self.items.items.len;
    }

    pub fn copy(self: *const ListTag, allocator: Allocator) !Tag {
        var list = ListTag.init(allocator, self.name);
        list.item_type = self.item_type;
        for (self.items.items) |*item| {
            try list.add(try item.copy(allocator));
        }
        return .{ .list = list };
    }
};

// ---------------------------------------------------------------------------
// Compound tag - named collection of tags
// ---------------------------------------------------------------------------

pub const CompoundTag = struct {
    name: []const u8,
    map: std.StringHashMap(Tag),

    pub fn init(allocator: Allocator, name: []const u8) CompoundTag {
        return .{
            .name = name,
            .map = std.StringHashMap(Tag).init(allocator),
        };
    }

    pub fn deinit(self: *CompoundTag, allocator: Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(allocator);
            allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }

    pub fn put(self: *CompoundTag, key: []const u8, value: Tag) !void {
        const owned_key = try self.map.allocator.dupe(u8, key);
        try self.map.put(owned_key, value);
    }

    pub fn get(self: *const CompoundTag, key: []const u8) ?*const Tag {
        return self.map.getPtr(key);
    }

    pub fn getMut(self: *CompoundTag, key: []const u8) ?*Tag {
        return self.map.getPtr(key);
    }

    pub fn contains(self: *const CompoundTag, key: []const u8) bool {
        return self.map.contains(key);
    }

    pub fn containsType(self: *const CompoundTag, key: []const u8, comptime tag_type: TagType) bool {
        if (self.map.getPtr(key)) |tag| {
            return tag.* == tag_type;
        }
        return false;
    }

    // Typed getters with defaults
    pub fn getByte(self: *const CompoundTag, key: []const u8) i8 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .byte) return tag.byte.data;
        }
        return 0;
    }

    pub fn getShort(self: *const CompoundTag, key: []const u8) i16 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .short) return tag.short.data;
        }
        return 0;
    }

    pub fn getInt(self: *const CompoundTag, key: []const u8) i32 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .int) return tag.int.data;
        }
        return 0;
    }

    pub fn getLong(self: *const CompoundTag, key: []const u8) i64 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .long) return tag.long.data;
        }
        return 0;
    }

    pub fn getFloat(self: *const CompoundTag, key: []const u8) f32 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .float) return tag.float.data;
        }
        return 0;
    }

    pub fn getDouble(self: *const CompoundTag, key: []const u8) f64 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .double) return tag.double.data;
        }
        return 0;
    }

    pub fn getString(self: *const CompoundTag, key: []const u8) []const u8 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .string) return tag.string.data;
        }
        return "";
    }

    pub fn getByteArray(self: *const CompoundTag, key: []const u8) []const u8 {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .byte_array) return tag.byte_array.data;
        }
        return &.{};
    }

    pub fn getList(self: *const CompoundTag, key: []const u8) ?*const ListTag {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .list) return &tag.list;
        }
        return null;
    }

    pub fn getCompound(self: *const CompoundTag, key: []const u8) ?*const CompoundTag {
        if (self.map.getPtr(key)) |tag| {
            if (tag.* == .compound) return &tag.compound;
        }
        return null;
    }

    pub fn getBoolean(self: *const CompoundTag, key: []const u8) bool {
        return self.getByte(key) != 0;
    }

    pub fn isEmpty(self: *const CompoundTag) bool {
        return self.map.count() == 0;
    }

    pub fn copy(self: *const CompoundTag, allocator: Allocator) !Tag {
        var compound = CompoundTag.init(allocator, self.name);
        var it = self.map.iterator();
        while (it.next()) |entry| {
            const tag_copy = try entry.value_ptr.*.copy(allocator);
            try compound.put(entry.key_ptr.*, tag_copy);
        }
        return .{ .compound = compound };
    }
};

// ---------------------------------------------------------------------------
// NBT Reader / Writer (using a simple byte buffer)
// ---------------------------------------------------------------------------

const ReadError = error{
    EndOfStream,
    InvalidTagType,
};

/// NBT reader from a byte buffer
pub const Reader = struct {
    data: []const u8,
    pos: usize,

    pub fn init(data: []const u8) Reader {
        return .{ .data = data, .pos = 0 };
    }

    fn readByte(self: *Reader) ReadError!u8 {
        if (self.pos >= self.data.len) return error.EndOfStream;
        const b = self.data[self.pos];
        self.pos += 1;
        return b;
    }

    fn readShort(self: *Reader) ReadError!i16 {
        const hi = try self.readByte();
        const lo = try self.readByte();
        return (@as(i16, hi) << 8) | lo;
    }

    fn readInt(self: *Reader) ReadError!i32 {
        const b0 = try self.readByte();
        const b1 = try self.readByte();
        const b2 = try self.readByte();
        const b3 = try self.readByte();
        return (@as(i32, b0) << 24) | (@as(i32, b1) << 16) | (@as(i32, b2) << 8) | b3;
    }

    fn readLong(self: *Reader) ReadError!i64 {
        const hi = try self.readInt();
        const lo = try self.readInt();
        return (@as(i64, @bitCast(hi)) << 32) | @as(i64, @bitCast(@as(u32, @bitCast(lo))));
    }

    fn readFloat(self: *Reader) ReadError!f32 {
        const bits = try self.readInt();
        return @bitCast(bits);
    }

    fn readDouble(self: *Reader) ReadError!f64 {
        const bits = try self.readLong();
        return @bitCast(bits);
    }

    fn readString(self: *Reader, allocator: Allocator) ReadError![]const u8 {
        const len = try self.readShort();
        if (len < 0) return error.InvalidTagType;
        const ulen: usize = @intCast(len);
        if (self.pos + ulen > self.data.len) return error.EndOfStream;
        const str = self.data[self.pos .. self.pos + ulen];
        self.pos += ulen;
        // Return slice pointing into the buffer (caller should dup if needed)
        _ = allocator;
        return str;
    }

    fn readBytes(self: *Reader, allocator: Allocator, length: usize) ReadError![]u8 {
        if (self.pos + length > self.data.len) return error.EndOfStream;
        const result = try allocator.alloc(u8, length);
        @memcpy(result, self.data[self.pos .. self.pos + length]);
        self.pos += length;
        return result;
    }

    /// Read a complete named NBT tag (includes type byte and name)
    pub fn readNamedTag(self: *Reader, allocator: Allocator) !Tag {
        const tag_type_byte = try self.readByte();
        if (tag_type_byte == @intFromEnum(TagType.end)) {
            return .end;
        }
        const tag_type: TagType = @enumFromInt(tag_type_byte);
        const name = blk: {
            const s = try self.readString(allocator);
            if (s.len > 0) {
                break :blk try allocator.dupe(u8, s);
            }
            break :blk &.{};
        };
        errdefer allocator.free(name);

        return switch (tag_type) {
            .end => .end,
            .byte => .{ .byte = .{ .name = name, .data = @bitCast(try self.readByte()) } },
            .short => .{ .short = .{ .name = name, .data = try self.readShort() } },
            .int => .{ .int = .{ .name = name, .data = try self.readInt() } },
            .long => .{ .long = .{ .name = name, .data = try self.readLong() } },
            .float => .{ .float = .{ .name = name, .data = try self.readFloat() } },
            .double => .{ .double = .{ .name = name, .data = try self.readDouble() } },
            .byte_array => blk: {
                const len = try self.readInt();
                const data = try self.readBytes(allocator, @intCast(len));
                break :blk .{ .byte_array = .{ .name = name, .data = data } };
            },
            .string => .{ .string = .{ .name = name, .data = try self.readString(allocator) } },
            .list => try self.readListPayload(allocator, name),
            .compound => try self.readCompoundPayload(allocator, name),
            _ => return error.InvalidTagType,
        };
    }

    fn readListPayload(self: *Reader, allocator: Allocator, name: []const u8) !Tag {
        const item_type_byte = try self.readByte();
        const item_type: TagType = @enumFromInt(item_type_byte);
        const size = try self.readInt();
        if (size < 0) return error.InvalidTagType;

        var list = ListTag.init(allocator, name);
        list.item_type = item_type;

        for (0..@intCast(size)) |_| {
            const tag = switch (item_type) {
                .end => Tag.end,
                .byte => .{ .byte = .{ .name = &.{}, .data = @as(i8, @bitCast(try self.readByte())) } },
                .short => .{ .short = .{ .name = &.{}, .data = try self.readShort() } },
                .int => .{ .int = .{ .name = &.{}, .data = try self.readInt() } },
                .long => .{ .long = .{ .name = &.{}, .data = try self.readLong() } },
                .float => .{ .float = .{ .name = &.{}, .data = try self.readFloat() } },
                .double => .{ .double = .{ .name = &.{}, .data = try self.readDouble() } },
                .byte_array => blk: {
                    const len = try self.readInt();
                    const data = try self.readBytes(allocator, @intCast(len));
                    break :blk .{ .byte_array = .{ .name = &.{}, .data = data } };
                },
                .string => .{ .string = .{ .name = &.{}, .data = try self.readString(allocator) } },
                .list => try self.readListPayload(allocator, &.{}),
                .compound => try self.readCompoundPayload(allocator, &.{}),
                _ => return error.InvalidTagType,
            };
            try list.add(tag);
        }

        return .{ .list = list };
    }

    fn readCompoundPayload(self: *Reader, allocator: Allocator, name: []const u8) !Tag {
        var compound = CompoundTag.init(allocator, name);

        while (true) {
            const tag_type_byte = try self.readByte();
            if (tag_type_byte == @intFromEnum(TagType.end)) break;
            const tag_type: TagType = @enumFromInt(tag_type_byte);
            const tag_name = blk: {
                const s = try self.readString(allocator);
                if (s.len > 0) break :blk try allocator.dupe(u8, s);
                break :blk &.{};
            };

            const tag = switch (tag_type) {
                .end => Tag.end,
                .byte => .{ .byte = .{ .name = tag_name, .data = @as(i8, @bitCast(try self.readByte())) } },
                .short => .{ .short = .{ .name = tag_name, .data = try self.readShort() } },
                .int => .{ .int = .{ .name = tag_name, .data = try self.readInt() } },
                .long => .{ .long = .{ .name = tag_name, .data = try self.readLong() } },
                .float => .{ .float = .{ .name = tag_name, .data = try self.readFloat() } },
                .double => .{ .double = .{ .name = tag_name, .data = try self.readDouble() } },
                .byte_array => blk: {
                    const len = try self.readInt();
                    const data = try self.readBytes(allocator, @intCast(len));
                    break :blk .{ .byte_array = .{ .name = tag_name, .data = data } };
                },
                .string => .{ .string = .{ .name = tag_name, .data = try self.readString(allocator) } },
                .list => try self.readListPayload(allocator, tag_name),
                .compound => try self.readCompoundPayload(allocator, tag_name),
                _ => return error.InvalidTagType,
            };
            try compound.put(tag_name, tag);
        }

        return .{ .compound = compound };
    }
};

/// NBT writer into a byte buffer
pub const Writer = struct {
    data: std.ArrayList(u8),

    pub fn init(allocator: Allocator) Writer {
        return .{ .data = std.ArrayList(u8).init(allocator) };
    }

    pub fn deinit(self: *Writer) void {
        self.data.deinit();
    }

    pub fn toOwnedSlice(self: *Writer) ![]u8 {
        return self.data.toOwnedSlice();
    }

    fn writeByte(self: *Writer, v: u8) !void {
        try self.data.append(v);
    }

    fn writeShort(self: *Writer, v: i16) !void {
        const bytes: [2]u8 = .{ @intCast(v >> 8), @intCast(v & 0xFF) };
        try self.data.appendSlice(&bytes);
    }

    fn writeInt(self: *Writer, v: i32) !void {
        const bytes: [4]u8 = .{
            @intCast(v >> 24),
            @intCast((v >> 16) & 0xFF),
            @intCast((v >> 8) & 0xFF),
            @intCast(v & 0xFF),
        };
        try self.data.appendSlice(&bytes);
    }

    fn writeLong(self: *Writer, v: i64) !void {
        try self.writeInt(@intCast(v >> 32));
        try self.writeInt(@intCast(v & 0xFFFFFFFF));
    }

    fn writeFloat(self: *Writer, v: f32) !void {
        try self.writeInt(@bitCast(v));
    }

    fn writeDouble(self: *Writer, v: f64) !void {
        try self.writeLong(@bitCast(v));
    }

    fn writeString(self: *Writer, s: []const u8) !void {
        try self.writeShort(@intCast(s.length));
        try self.data.appendSlice(s);
    }

    fn writeBytes(self: *Writer, data: []const u8) !void {
        self.data.appendSlice(data) catch {};
    }

    /// Write a named NBT tag
    pub fn writeNamedTag(self: *Writer, tag: *const Tag) !void {
        const tag_type = tag.getType();
        try self.writeByte(@intFromEnum(tag_type));
        if (tag_type == .end) return;

        try self.writeString(tag.getName());

        switch (tag.*) {
            .end => {},
            .byte => |t| try self.writeByte(@bitCast(t.data)),
            .short => |t| try self.writeShort(t.data),
            .int => |t| try self.writeInt(t.data),
            .long => |t| try self.writeLong(t.data),
            .float => |t| try self.writeFloat(t.data),
            .double => |t| try self.writeDouble(t.data),
            .byte_array => |t| {
                try self.writeInt(@intCast(t.data.len));
                try self.data.appendSlice(t.data);
            },
            .string => |t| try self.writeString(t.data),
            .list => |*t| {
                try self.writeByte(@intFromEnum(t.item_type));
                try self.writeInt(@intCast(t.items.items.len));
                for (t.items.items) |*item| {
                    try self.writePayload(item);
                }
            },
            .compound => |*t| {
                var it = t.map.iterator();
                while (it.next()) |entry| {
                    try self.writeNamedTag(entry.value_ptr);
                }
                try self.writeByte(@intFromEnum(TagType.end));
            },
        }
    }

    fn writePayload(self: *Writer, tag: *const Tag) !void {
        switch (tag.*) {
            .end => {},
            .byte => |t| try self.writeByte(@bitCast(t.data)),
            .short => |t| try self.writeShort(t.data),
            .int => |t| try self.writeInt(t.data),
            .long => |t| try self.writeLong(t.data),
            .float => |t| try self.writeFloat(t.data),
            .double => |t| try self.writeDouble(t.data),
            .byte_array => |t| {
                try self.writeInt(@intCast(t.data.len));
                try self.data.appendSlice(t.data);
            },
            .string => |t| try self.writeString(t.data),
            .list => try self.writeNamedTag(tag),
            .compound => try self.writeNamedTag(tag),
        }
    }
};

// ---------------------------------------------------------------------------
// Convenience builders
// ---------------------------------------------------------------------------

pub fn newByte(name: []const u8, value: i8) Tag {
    return .{ .byte = .{ .name = name, .data = value } };
}

pub fn newShort(name: []const u8, value: i16) Tag {
    return .{ .short = .{ .name = name, .data = value } };
}

pub fn newInt(name: []const u8, value: i32) Tag {
    return .{ .int = .{ .name = name, .data = value } };
}

pub fn newLong(name: []const u8, value: i64) Tag {
    return .{ .long = .{ .name = name, .data = value } };
}

pub fn newFloat(name: []const u8, value: f32) Tag {
    return .{ .float = .{ .name = name, .data = value } };
}

pub fn newDouble(name: []const u8, value: f64) Tag {
    return .{ .double = .{ .name = name, .data = value } };
}

pub fn newString(name: []const u8, value: []const u8) Tag {
    return .{ .string = .{ .name = name, .data = value } };
}

pub fn newByteArray(name: []const u8, value: []u8) Tag {
    return .{ .byte_array = .{ .name = name, .data = value } };
}

pub fn newBoolean(name: []const u8, value: bool) Tag {
    return newByte(name, if (value) 1 else 0);
}

pub fn newCompound(allocator: Allocator, name: []const u8) Tag {
    return .{ .compound = CompoundTag.init(allocator, name) };
}

pub fn newList(allocator: Allocator, name: []const u8) Tag {
    return .{ .list = ListTag.init(allocator, name) };
}
