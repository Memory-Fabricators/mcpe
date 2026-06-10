//! Bit-level serialization / deserialization.
//! Ported from BitStream.h / BitStream.cpp
//! Zig 0.16

const std = @import("std");

const types = @import("types.zig");
const BitSize = types.BitSize;

/// Stack allocation size before heap allocation
const stack_allocation_size: usize = 256;

/// Compute bytes needed for a number of bits
pub fn bitsToBytes(bits: anytype) usize {
    return (@as(usize, @intCast(bits)) + 7) >> 3;
}

pub fn bytesToBits(bytes: anytype) usize {
    return @as(usize, @intCast(bytes)) << 3;
}

/// BitStream for reading/writing bits.
/// Uses the Zig allocator pattern.
pub const BitStream = struct {
    /// The data buffer
    data: []u8,
    /// Number of bits used (write offset)
    num_bits_used: BitSize,
    /// Number of bits allocated
    num_bits_allocated: BitSize,
    /// Current read offset in bits
    read_offset: BitSize,
    /// Whether we own the data and should free it
    owns_data: bool,
    /// Allocator to use
    allocator: std.mem.Allocator,

    /// Stack buffer for small allocations
    stack_data: [stack_allocation_size]u8 = undefined,

    /// Create a new empty BitStream
    pub fn init(allocator: std.mem.Allocator) BitStream {
        return .{
            .data = &.{},
            .num_bits_used = 0,
            .num_bits_allocated = 0,
            .read_offset = 0,
            .owns_data = true,
            .allocator = allocator,
        };
    }

    /// Create a BitStream that wraps existing data (for reading).
    /// The data is NOT copied - caller owns it.
    pub fn initFromData(data: []const u8) BitStream {
        return .{
            .data = @constCast(data),
            .num_bits_used = @intCast(data.len * 8),
            .num_bits_allocated = @intCast(data.len * 8),
            .read_offset = 0,
            .owns_data = false,
            .allocator = undefined,
        };
    }

    /// Create with pre-allocated capacity
    pub fn initCapacity(allocator: std.mem.Allocator, initial_bytes: usize) !BitStream {
        const data = try allocator.alloc(u8, initial_bytes);
        @memset(data, 0);
        return .{
            .data = data,
            .num_bits_used = 0,
            .num_bits_allocated = @intCast(initial_bytes * 8),
            .read_offset = 0,
            .owns_data = true,
            .allocator = allocator,
        };
    }

    /// Free the BitStream's owned data
    pub fn deinit(self: *BitStream) void {
        if (self.owns_data and self.data.len > 0) {
            self.allocator.free(self.data);
            self.data = &.{};
        }
    }

    /// Reset the bitstream for reuse (keeps allocated buffer)
    pub fn reset(self: *BitStream) void {
        self.num_bits_used = 0;
        self.read_offset = 0;
    }

    /// Reset the read pointer to the beginning
    pub fn resetReadPointer(self: *BitStream) void {
        self.read_offset = 0;
    }

    /// Reset the write pointer to the beginning
    pub fn resetWritePointer(self: *BitStream) void {
        self.num_bits_used = 0;
    }

    /// Get the current write offset in bits
    pub fn getWriteOffset(self: *const BitStream) BitSize {
        return self.num_bits_used;
    }

    /// Get the number of bits used
    pub fn getNumberOfBitsUsed(self: *const BitStream) BitSize {
        return self.num_bits_used;
    }

    /// Get the number of bytes used
    pub fn getNumberOfBytesUsed(self: *const BitStream) usize {
        return bitsToBytes(self.num_bits_used);
    }

    /// Get the read offset
    pub fn getReadOffset(self: *const BitStream) BitSize {
        return self.read_offset;
    }

    /// Set the read offset
    pub fn setReadOffset(self: *BitStream, offset: BitSize) void {
        self.read_offset = offset;
    }

    /// Get number of unread bits
    pub fn getNumberOfUnreadBits(self: *const BitStream) BitSize {
        return self.num_bits_used - self.read_offset;
    }

    /// Get a pointer to the raw data
    pub fn getData(self: *const BitStream) []const u8 {
        return self.data;
    }

    /// Get owned slice of data (caller takes ownership, BitStream is reset)
    pub fn toOwnedSlice(self: *BitStream) []u8 {
        const len = self.getNumberOfBytesUsed();
        const result = self.allocator.alloc(u8, len) catch @panic("OOM");
        @memcpy(result, self.data[0..len]);
        return result;
    }

    // ----------------------------------------------------------------
    // Write helpers
    // ----------------------------------------------------------------

    /// Ensure we have enough space for `num_bits` more bits
    fn addBitsAndReallocate(self: *BitStream, num_bits: BitSize) !void {
        const new_num_bits = self.num_bits_used + num_bits;
        if (new_num_bits <= self.num_bits_allocated) return;

        // Grow by at least 2x
        var new_allocated = self.num_bits_allocated * 2;
        if (new_allocated < stack_allocation_size * 8) {
            new_allocated = stack_allocation_size * 8;
        }
        if (new_allocated < new_num_bits) {
            new_allocated = new_num_bits + (new_num_bits >> 1); // 1.5x
        }

        const new_bytes = bitsToBytes(new_allocated);
        if (self.owns_data) {
            self.data = try self.allocator.realloc(self.data, new_bytes);
        } else {
            // Switch to owning mode
            const new_data = try self.allocator.alloc(u8, new_bytes);
            @memcpy(new_data[0..self.data.len], self.data);
            @memset(new_data[self.data.len..], 0);
            self.data = new_data;
            self.owns_data = true;
        }
        self.num_bits_allocated = @intCast(new_bytes * 8);
    }

    /// Write a single bit
    pub fn writeBit(self: *BitStream, value: bool) !void {
        try self.addBitsAndReallocate(1);
        const byte_offset = self.num_bits_used >> 3;
        const bit_offset = self.num_bits_used & 7;
        if (value) {
            self.data[byte_offset] |= @as(u8, 0x80) >> @intCast(bit_offset);
        } else {
            self.data[byte_offset] &= ~(@as(u8, 0x80) >> @intCast(bit_offset));
        }
        self.num_bits_used += 1;
    }

    /// Write a 0 bit
    pub fn write0(self: *BitStream) !void {
        try self.writeBit(false);
    }

    /// Write a 1 bit
    pub fn write1(self: *BitStream) !void {
        try self.writeBit(true);
    }

    /// Read a single bit
    pub fn readBit(self: *BitStream) !bool {
        if (self.read_offset + 1 > self.num_bits_used) return error.EndOfStream;
        const byte_offset = self.read_offset >> 3;
        const bit_offset = self.read_offset & 7;
        const bit: u8 = (self.data[byte_offset] >> @intCast(7 - bit_offset)) & 1;
        self.read_offset += 1;
        return bit != 0;
    }

    /// Write raw bits from a byte array
    pub fn writeBits(self: *BitStream, input: []const u8, num_bits: BitSize, right_aligned: bool) !void {
        if (num_bits == 0) return;
        try self.addBitsAndReallocate(num_bits);

        const num_bytes = bitsToBytes(num_bits);
        for (0..num_bytes) |i| {
            const src_byte = if (i < input.len) input[i] else 0;
            const bits_remaining: usize = @intCast(@min(8, num_bits - @as(BitSize, @intCast(i * 8))));

            const dest_byte_offset = (self.num_bits_used >> 3) + @as(usize, @intCast(i));
            const dest_bit_offset = self.num_bits_used & 7;

            if (dest_bit_offset == 0 and bits_remaining == 8) {
                // Byte-aligned, full byte copy
                self.data[dest_byte_offset] = src_byte;
            } else {
                // Partial byte write
                const shift: u3 = @intCast(dest_bit_offset);
                if (right_aligned) {
                    const mask: u8 = @as(u8, 0xFF) >> @intCast(8 - bits_remaining);
                    self.data[dest_byte_offset] &= ~(mask >> shift);
                    self.data[dest_byte_offset] |= (src_byte & mask) >> shift;
                } else {
                    self.data[dest_byte_offset] &= @as(u8, 0xFF) >> @intCast(@as(u4, 8) - shift);
                    const val: u8 = src_byte & (@as(u8, 0xFF) << @intCast(8 - bits_remaining));
                    self.data[dest_byte_offset] |= val >> shift;
                }
                // Handle overflow into next byte
                if (shift + bits_remaining > 8) {
                    const overflow_bits = shift + @as(u8, @intCast(bits_remaining)) - 8;
                    const mask: u8 = @as(u8, 0xFF) << @intCast(8 - overflow_bits);
                    self.data[dest_byte_offset + 1] &= ~mask;
                    if (right_aligned) {
                        self.data[dest_byte_offset + 1] |= (src_byte << @intCast(@as(u4, 8) - shift)) & mask;
                    } else {
                        self.data[dest_byte_offset + 1] |= (src_byte << @intCast(@as(u4, 8) - shift)) & mask;
                    }
                }
            }
        }
        self.num_bits_used += num_bits;
    }

    /// Read raw bits into a byte array
    pub fn readBits(self: *BitStream, output: []u8, num_bits: BitSize, align_right: bool) !void {
        if (num_bits == 0) return;
        if (self.read_offset + num_bits > self.num_bits_used) return error.EndOfStream;

        const num_bytes = bitsToBytes(num_bits);
        @memset(output[0..num_bytes], 0);

        for (0..num_bytes) |i| {
            const bits_remaining: usize = @intCast(@min(8, num_bits - @as(BitSize, @intCast(i * 8))));
            const src_byte_offset = (self.read_offset >> 3) + @as(usize, @intCast(i));
            const src_bit_offset = self.read_offset & 7;

            if (src_bit_offset == 0 and bits_remaining == 8) {
                output[i] = self.data[src_byte_offset];
            } else {
                const shift: u3 = @intCast(src_bit_offset);
                const mask: u8 = if (bits_remaining == 8) 0xFF else (@as(u8, 1) << @intCast(bits_remaining)) - 1;
                if (align_right) {
                    output[i] = (self.data[src_byte_offset] << shift) & mask;
                    if (shift + bits_remaining > 8 and src_byte_offset + 1 < self.data.len) {
                        const overflow: u3 = @intCast(@as(u4, 8) - shift);
                        output[i] |= (self.data[src_byte_offset + 1] >> overflow) & mask;
                    }
                } else {
                    output[i] = self.data[src_byte_offset] & (mask << @intCast(@as(u4, 8) - shift));
                    if (shift + bits_remaining > 8 and src_byte_offset + 1 < self.data.len) {
                        const overflow: u3 = @intCast(@as(u4, 8) - shift);
                        output[i] |= self.data[src_byte_offset + 1] >> overflow;
                    }
                }
            }
        }
        self.read_offset += num_bits;
    }

    // ----------------------------------------------------------------
    // Aligned byte operations
    // ----------------------------------------------------------------

    /// Align write pointer to byte boundary
    pub fn alignWriteToByteBoundary(self: *BitStream) void {
        self.num_bits_used += 8 - (@as(u8, @intCast((self.num_bits_used - 1) & 7)) + 1);
    }

    /// Align read pointer to byte boundary
    pub fn alignReadToByteBoundary(self: *BitStream) void {
        self.read_offset += 8 - @as(BitSize, @intCast((self.read_offset - 1) & 7)) - 1;
    }

    /// Write aligned bytes (byte-aligned)
    pub fn writeAlignedBytes(self: *BitStream, input: []const u8) !void {
        self.alignWriteToByteBoundary();
        try self.addBitsAndReallocate(@intCast(input.len * 8));
        const offset = self.num_bits_used >> 3;
        @memcpy(self.data[offset..][0..input.len], input);
        self.num_bits_used += @as(BitSize, @intCast(input.len * 8));
    }

    /// Read aligned bytes (byte-aligned)
    pub fn readAlignedBytes(self: *BitStream, output: []u8) !void {
        self.alignReadToByteBoundary();
        const num_bits: BitSize = @intCast(output.len * 8);
        if (self.read_offset + num_bits > self.num_bits_used) return error.EndOfStream;
        const offset = self.read_offset >> 3;
        @memcpy(output, self.data[offset..][0..output.len]);
        self.read_offset += num_bits;
    }

    // ----------------------------------------------------------------
    // Write / Read for standard types
    // ----------------------------------------------------------------

    /// Write a u8
    pub fn writeU8(self: *BitStream, value: u8) !void {
        try self.writeBits(std.mem.asBytes(&value), 8, true);
    }

    /// Read a u8
    pub fn readU8(self: *BitStream) !u8 {
        var result: u8 = 0;
        try self.readBits(std.mem.asBytes(&result), 8, true);
        return result;
    }

    /// Write a u16
    pub fn writeU16(self: *BitStream, value: u16) !void {
        const bytes: [2]u8 = .{ @truncate(value >> 8), @truncate(value & 0xFF) };
        try self.writeBits(&bytes, 16, true);
    }

    /// Read a u16
    pub fn readU16(self: *BitStream) !u16 {
        var bytes: [2]u8 = .{ 0, 0 };
        try self.readBits(&bytes, 16, true);
        return (@as(u16, bytes[0]) << 8) | bytes[1];
    }

    /// Write a u32
    pub fn writeU32(self: *BitStream, value: u32) !void {
        const bytes: [4]u8 = .{
            @truncate(value >> 24),
            @truncate(value >> 16),
            @truncate(value >> 8),
            @truncate(value & 0xFF),
        };
        try self.writeBits(&bytes, 32, true);
    }

    /// Read a u32
    pub fn readU32(self: *BitStream) !u32 {
        var bytes: [4]u8 = .{ 0, 0, 0, 0 };
        try self.readBits(&bytes, 32, true);
        return (@as(u32, bytes[0]) << 24) | (@as(u32, bytes[1]) << 16) | (@as(u32, bytes[2]) << 8) | bytes[3];
    }

    /// Write a u64
    pub fn writeU64(self: *BitStream, value: u64) !void {
        const bytes: [8]u8 = .{
            @truncate(value >> 56),
            @truncate(value >> 48),
            @truncate(value >> 40),
            @truncate(value >> 32),
            @truncate(value >> 24),
            @truncate(value >> 16),
            @truncate(value >> 8),
            @truncate(value & 0xFF),
        };
        try self.writeBits(&bytes, 64, true);
    }

    /// Read a u64
    pub fn readU64(self: *BitStream) !u64 {
        var bytes: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
        try self.readBits(&bytes, 64, true);
        return (@as(u64, bytes[0]) << 56) | (@as(u64, bytes[1]) << 48) | (@as(u64, bytes[2]) << 40) |
            (@as(u64, bytes[3]) << 32) | (@as(u64, bytes[4]) << 24) | (@as(u64, bytes[5]) << 16) |
            (@as(u64, bytes[6]) << 8) | bytes[7];
    }

    /// Write a bool (as 1 bit)
    pub fn writeBool(self: *BitStream, value: bool) !void {
        try self.writeBit(value);
    }

    /// Read a bool
    pub fn readBool(self: *BitStream) !bool {
        return try self.readBit();
    }

    /// Write a float (32-bit IEEE 754, big-endian)
    pub fn writeF32(self: *BitStream, value: f32) !void {
        try self.writeU32(@bitCast(value));
    }

    /// Read a float
    pub fn readF32(self: *BitStream) !f32 {
        const bits = try self.readU32();
        return @bitCast(bits);
    }

    /// Write a f64 (double)
    pub fn writeF64(self: *BitStream, value: f64) !void {
        try self.writeU64(@bitCast(value));
    }

    /// Read a f64
    pub fn readF64(self: *BitStream) !f64 {
        const bits = try self.readU64();
        return @bitCast(bits);
    }

    /// Write a slice of bytes (length-prefixed with u16)
    pub fn writeBytes(self: *BitStream, data: []const u8) !void {
        try self.writeU16(@intCast(data.len));
        if (data.len > 0) {
            try self.writeAlignedBytes(data);
        }
    }

    /// Read a length-prefixed byte slice (caller owns the returned memory)
    pub fn readBytesAlloc(self: *BitStream, allocator: std.mem.Allocator) ![]u8 {
        const len = try self.readU16();
        if (len == 0) return &.{};
        const result = try allocator.alloc(u8, len);
        errdefer allocator.free(result);
        try self.readAlignedBytes(result);
        return result;
    }

    /// Write a Zig string (length-prefixed)
    pub fn writeString(self: *BitStream, str: []const u8) !void {
        try self.writeU16(@intCast(str.len));
        if (str.len > 0) {
            try self.writeAlignedBytes(str);
        }
    }

    /// Read a length-prefixed string (caller owns memory)
    pub fn readStringAlloc(self: *BitStream, allocator: std.mem.Allocator) ![]u8 {
        return try self.readBytesAlloc(allocator);
    }

    // ----------------------------------------------------------------
    // Compressed writes (saves bandwidth for small values)
    // ----------------------------------------------------------------

    /// Write a compressed u32 (variable-length encoding)
    pub fn writeCompressedU32(self: *BitStream, value: u32) !void {
        var v = value;
        // Use the same scheme as original RakNet
        if (v < 0x80) {
            try self.writeU8(@intCast(v));
            return;
        }
        try self.writeU8(@as(u8, 0x80) | @as(u8, @intCast(v & 0x7F)));
        v >>= 7;
        while (v >= 0x80) {
            try self.writeU8(@as(u8, 0x80) | @as(u8, @intCast(v & 0x7F)));
            v >>= 7;
        }
        try self.writeU8(@intCast(v & 0x7F));
    }

    /// Read a compressed u32
    pub fn readCompressedU32(self: *BitStream) !u32 {
        var result: u32 = 0;
        var shift: u5 = 0;
        while (true) {
            const b = try self.readU8();
            result |= @as(u32, b & 0x7F) << shift;
            if ((b & 0x80) == 0) break;
            shift += 7;
        }
        return result;
    }

    /// Write a compressed u16
    pub fn writeCompressedU16(self: *BitStream, value: u16) !void {
        try self.writeCompressedU32(value);
    }

    /// Read a compressed u16
    pub fn readCompressedU16(self: *BitStream) !u16 {
        return @intCast(try self.readCompressedU32());
    }

    // ----------------------------------------------------------------
    // Utility
    // ----------------------------------------------------------------

    /// Ignore a number of bits (advance read pointer)
    pub fn ignoreBits(self: *BitStream, num_bits: BitSize) !void {
        if (self.read_offset + num_bits > self.num_bits_used) return error.EndOfStream;
        self.read_offset += num_bits;
    }

    /// Ignore a number of bytes (advance read pointer)
    pub fn ignoreBytes(self: *BitStream, num_bytes: usize) !void {
        try self.ignoreBits(@intCast(num_bytes * 8));
    }

    /// Pad with zeros to the specified byte length
    pub fn padWithZeroToByteLength(self: *BitStream, bytes: usize) !void {
        const target_bits: BitSize = @intCast(bytes * 8);
        if (target_bits <= self.num_bits_used) return;
        const pad_bits = target_bits - self.num_bits_used;
        try self.addBitsAndReallocate(pad_bits);
        self.num_bits_used = target_bits;
    }

    /// Get number of leading zeros in a byte
    pub fn numberOfLeadingZeroesU8(x: u8) u8 {
        return @clz(x) - 24;
    }

    /// Get number of leading zeros in a u16
    pub fn numberOfLeadingZeroesU16(x: u16) u8 {
        return @intCast(@clz(x) - 16);
    }

    /// Get number of leading zeros in a u32
    pub fn numberOfLeadingZeroesU32(x: u32) u8 {
        return @intCast(@clz(x));
    }

    /// Get number of leading zeros in a u64
    pub fn numberOfLeadingZeroesU64(x: u64) u8 {
        return @intCast(@clz(x));
    }
};

// ----------------------------------------------------------------
// Generic write/read functions using anytype
// ----------------------------------------------------------------

/// Write any supported integer type to the bitstream
pub fn write(bs: *BitStream, value: anytype) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Bool => try bs.writeBool(value),
        .Int => |info| switch (info.bits) {
            8 => try bs.writeU8(@intCast(value)),
            16 => try bs.writeU16(@intCast(value)),
            32 => try bs.writeU32(@intCast(value)),
            64 => try bs.writeU64(@intCast(value)),
            else => @compileError("Unsupported integer size: " ++ @typeName(T)),
        },
        .Float => |info| switch (info.bits) {
            32 => try bs.writeF32(value),
            64 => try bs.writeF64(value),
            else => @compileError("Unsupported float size: " ++ @typeName(T)),
        },
        .Enum => try bs.writeU8(@intFromEnum(value)),
        else => @compileError("Unsupported type for write: " ++ @typeName(T)),
    }
}

/// Read any supported integer type from the bitstream
pub fn read(bs: *BitStream, comptime T: type) !T {
    switch (@typeInfo(T)) {
        .Bool => return try bs.readBool(),
        .Int => |info| switch (info.bits) {
            8 => return @intCast(try bs.readU8()),
            16 => return @intCast(try bs.readU16()),
            32 => return @intCast(try bs.readU32()),
            64 => return @intCast(try bs.readU64()),
            else => @compileError("Unsupported integer size: " ++ @typeName(T)),
        },
        .Float => |info| switch (info.bits) {
            32 => return try bs.readF32(),
            64 => return try bs.readF64(),
            else => @compileError("Unsupported float size: " ++ @typeName(T)),
        },
        .Enum => {
            const raw = try bs.readU8();
            return @enumFromInt(raw);
        },
        else => @compileError("Unsupported type for read: " ++ @typeName(T)),
    }
}
