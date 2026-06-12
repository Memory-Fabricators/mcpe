//! save.zig – Binary chunk save/load (MCPE 0.1 compatible data layout).

const std = @import("std");
const chunk = @import("chunk.zig");
const DataLayer = chunk.DataLayer;

const MAGIC: [4]u8 = .{ 'M', 'C', 'P', 'E' };
const VERSION: u8 = 1;
const BLOCKS_LEN: u32 = 32768;
const LIGHT_LEN: u32 = 16384;
const HEIGHTMAP_LEN: u32 = 256;

pub const LevelDat = struct {
    seed: i64,
    time: u64,
};

pub fn saveChunk(
    allocator: std.mem.Allocator,
    world_dir: []const u8,
    blocks: []const u8,
    skylight: DataLayer,
    blocklight: DataLayer,
    heightmap: [256]i8,
    x: i32,
    z: i32,
) !void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    cwd.createDirPath(io, world_dir) catch {};

    const path = try std.fmt.allocPrint(allocator, "{s}/c.{d}.{d}.dat", .{ world_dir, x, z });
    defer allocator.free(path);

    const file = try cwd.createFile(io, path, .{});
    defer file.close(io);

    var off: u64 = 0;
    var buf: [32]u8 = undefined;

    _ = try file.writePositionalAll(io, &MAGIC, off);
    off += MAGIC.len;
    std.mem.writeInt(u8, buf[0..1], VERSION, .little);
    _ = try file.writePositionalAll(io, buf[0..1], off);
    off += 1;
    std.mem.writeInt(i32, buf[0..4], x, .little);
    _ = try file.writePositionalAll(io, buf[0..4], off);
    off += 4;
    std.mem.writeInt(i32, buf[0..4], z, .little);
    _ = try file.writePositionalAll(io, buf[0..4], off);
    off += 4;

    std.mem.writeInt(u32, buf[0..4], BLOCKS_LEN, .little);
    _ = try file.writePositionalAll(io, buf[0..4], off);
    off += 4;
    _ = try file.writePositionalAll(io, blocks, off);
    off += BLOCKS_LEN;

    std.mem.writeInt(u32, buf[0..4], LIGHT_LEN, .little);
    _ = try file.writePositionalAll(io, buf[0..4], off);
    off += 4;
    _ = try file.writePositionalAll(io, skylight.data, off);
    off += LIGHT_LEN;

    std.mem.writeInt(u32, buf[0..4], LIGHT_LEN, .little);
    _ = try file.writePositionalAll(io, buf[0..4], off);
    off += 4;
    _ = try file.writePositionalAll(io, blocklight.data, off);
    off += LIGHT_LEN;

    std.mem.writeInt(u32, buf[0..4], HEIGHTMAP_LEN, .little);
    _ = try file.writePositionalAll(io, buf[0..4], off);
    off += 4;
    _ = try file.writePositionalAll(io, std.mem.sliceAsBytes(&heightmap), off);
}

pub fn loadChunk(
    allocator: std.mem.Allocator,
    world_dir: []const u8,
    x: i32,
    z: i32,
) !?struct {
    blocks: []u8,
    skylight: DataLayer,
    blocklight: DataLayer,
    heightmap: [256]i8,
    x: i32,
    z: i32,
} {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const path = try std.fmt.allocPrint(allocator, "{s}/c.{d}.{d}.dat", .{ world_dir, x, z });
    defer allocator.free(path);

    const file = cwd.openFile(io, path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close(io);

    const file_size = (try file.stat(io)).size;
    const raw = try allocator.alloc(u8, file_size);
    defer allocator.free(raw);
    _ = try file.readPositionalAll(io, raw, 0);

    var pos: usize = 0;
    if (pos + 4 > raw.len) return error.UnexpectedEof;
    if (!std.mem.eql(u8, raw[pos..][0..4], &MAGIC)) return error.BadMagic;
    pos += 4;
    if (pos + 1 > raw.len) return error.UnexpectedEof;
    if (raw[pos] != VERSION) return error.UnsupportedVersion;
    pos += 1;
    if (pos + 8 > raw.len) return error.UnexpectedEof;
    const fx = std.mem.readInt(i32, raw[pos..][0..4], .little);
    pos += 4;
    const fz = std.mem.readInt(i32, raw[pos..][0..4], .little);
    pos += 4;
    if (fx != x or fz != z) return error.PositionMismatch;

    if (pos + 4 > raw.len) return error.UnexpectedEof;
    const blen = std.mem.readInt(u32, raw[pos..][0..4], .little);
    pos += 4;
    if (blen != BLOCKS_LEN) return error.BadBlockCount;
    if (pos + blen > raw.len) return error.UnexpectedEof;
    const blocks = try allocator.alloc(u8, BLOCKS_LEN);
    errdefer allocator.free(blocks);
    @memcpy(blocks, raw[pos..][0..BLOCKS_LEN]);
    pos += BLOCKS_LEN;

    if (pos + 4 > raw.len) return error.UnexpectedEof;
    const slen = std.mem.readInt(u32, raw[pos..][0..4], .little);
    pos += 4;
    if (slen != LIGHT_LEN) return error.BadLightCount;
    if (pos + slen > raw.len) return error.UnexpectedEof;
    var skylight = try DataLayer.init(allocator, BLOCKS_LEN);
    errdefer skylight.deinit(allocator);
    @memcpy(skylight.data, raw[pos..][0..LIGHT_LEN]);
    pos += LIGHT_LEN;

    if (pos + 4 > raw.len) return error.UnexpectedEof;
    const llen = std.mem.readInt(u32, raw[pos..][0..4], .little);
    pos += 4;
    if (llen != LIGHT_LEN) return error.BadLightCount;
    if (pos + llen > raw.len) return error.UnexpectedEof;
    var blocklight = try DataLayer.init(allocator, BLOCKS_LEN);
    errdefer blocklight.deinit(allocator);
    @memcpy(blocklight.data, raw[pos..][0..LIGHT_LEN]);
    pos += LIGHT_LEN;

    if (pos + 4 > raw.len) return error.UnexpectedEof;
    const hlen = std.mem.readInt(u32, raw[pos..][0..4], .little);
    pos += 4;
    if (hlen != HEIGHTMAP_LEN) return error.BadHeightmapSize;
    if (pos + hlen > raw.len) return error.UnexpectedEof;
    var hmap: [256]i8 = undefined;
    @memcpy(std.mem.sliceAsBytes(&hmap), raw[pos..][0..HEIGHTMAP_LEN]);

    return .{
        .blocks = blocks,
        .skylight = skylight,
        .blocklight = blocklight,
        .heightmap = hmap,
        .x = fx,
        .z = fz,
    };
}

pub fn saveLevelDat(allocator: std.mem.Allocator, world_dir: []const u8, seed: i64, time: u64) !void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    cwd.createDirPath(io, world_dir) catch {};

    const path = try std.fmt.allocPrint(allocator, "{s}/level.dat", .{world_dir});
    defer allocator.free(path);

    const file = try cwd.createFile(io, path, .{});
    defer file.close(io);

    var buf: [32]u8 = undefined;
    var off: u64 = 0;

    _ = try file.writePositionalAll(io, &[_]u8{ 'L', 'V', 'L', 'D' }, off);
    off += 4;
    buf[0] = 1;
    _ = try file.writePositionalAll(io, buf[0..1], off);
    off += 1;
    std.mem.writeInt(i64, buf[0..8], seed, .little);
    _ = try file.writePositionalAll(io, buf[0..8], off);
    off += 8;
    std.mem.writeInt(u64, buf[0..8], time, .little);
    _ = try file.writePositionalAll(io, buf[0..8], off);
}

pub fn loadLevelDat(allocator: std.mem.Allocator, world_dir: []const u8) !?LevelDat {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    const path = try std.fmt.allocPrint(allocator, "{s}/level.dat", .{world_dir});
    defer allocator.free(path);

    const file = cwd.openFile(io, path, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close(io);

    const file_size = (try file.stat(io)).size;
    const raw = try allocator.alloc(u8, file_size);
    defer allocator.free(raw);
    _ = try file.readPositionalAll(io, raw, 0);

    if (raw.len < 17) return error.BadFormat;
    if (!std.mem.eql(u8, raw[0..4], &[_]u8{ 'L', 'V', 'L', 'D' })) return error.BadMagic;

    const seed = std.mem.readInt(i64, raw[5..13], .little);
    const time = std.mem.readInt(u64, raw[13..21], .little);
    return LevelDat{ .seed = seed, .time = time };
}
