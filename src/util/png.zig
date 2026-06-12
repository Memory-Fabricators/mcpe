const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PngImage = struct {
    width: u32,
    height: u32,
    pixels: []u8,

    pub fn deinit(self: PngImage, allocator: Allocator) void {
        allocator.free(self.pixels);
    }
};

fn paethPredictor(a: u8, b: u8, c: u8) u8 {
    const ia = @as(i16, a);
    const ib = @as(i16, b);
    const ic = @as(i16, c);
    const p = ia + ib - ic;
    const pa = @abs(p - ia);
    const pb = @abs(p - ib);
    const pc = @abs(p - ic);
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}

pub fn loadPng(allocator: Allocator, file_path: []const u8) !PngImage {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, file_path, .{ .mode = .read_only });
    defer file.close(io);

    const file_size = (try file.stat(io)).size;
    const file_bytes = try allocator.alloc(u8, file_size);
    defer allocator.free(file_bytes);

    const bytes_read = try file.readPositionalAll(io, file_bytes, 0);
    if (bytes_read != file_size) return error.FileReadIncomplete;

    if (file_bytes.len < 8 or !std.mem.eql(u8, file_bytes[0..8], &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 })) {
        return error.InvalidPngSignature;
    }

    var idx: usize = 8;
    var width: u32 = 0;
    var height: u32 = 0;

    var compressed_idat = std.ArrayList(u8).empty;
    defer compressed_idat.deinit(allocator);

    while (idx < file_bytes.len) {
        if (idx + 12 > file_bytes.len) break;

        const chunk_len = std.mem.readInt(u32, file_bytes[idx..][0..4], .big);
        const chunk_type = file_bytes[idx + 4 .. idx + 8];
        idx += 8;

        if (idx + chunk_len + 4 > file_bytes.len) return error.TruncatedChunkData;
        const chunk_data = file_bytes[idx .. idx + chunk_len];
        idx += chunk_len + 4;

        if (std.mem.eql(u8, chunk_type, "IHDR")) {
            width = std.mem.readInt(u32, chunk_data[0..4], .big);
            height = std.mem.readInt(u32, chunk_data[4..8], .big);

            if (chunk_data[8] != 8 or chunk_data[9] != 6) return error.UnsupportedFormat;
        } else if (std.mem.eql(u8, chunk_type, "IDAT")) {
            try compressed_idat.appendSlice(allocator, chunk_data);
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            break;
        }
    }

    const mem_reader: std.Io.Reader = .fixed(compressed_idat.items);

    const window_buf = try allocator.alloc(u8, std.compress.flate.max_window_len);
    defer allocator.free(window_buf);

    var zlib_stream = std.compress.flate.Decompress.init(@constCast(&mem_reader), .zlib, window_buf);

    const stride = width * 4;
    const decompressed_len = (stride + 1) * height;
    const decompressed = try allocator.alloc(u8, decompressed_len);
    defer allocator.free(decompressed);

    try zlib_stream.reader.readSliceAll(decompressed);

    var pixels = try allocator.alloc(u8, stride * height);
    errdefer allocator.free(pixels);

    var y: usize = 0;
    while (y < height) : (y += 1) {
        const src_row_start = y * (stride + 1);
        const filter_type = decompressed[src_row_start];
        const src_row = decompressed[src_row_start + 1 .. src_row_start + 1 + stride];
        const dest_row = pixels[y * stride .. (y + 1) * stride];

        switch (filter_type) {
            0 => std.mem.copyForwards(u8, dest_row, src_row),
            1 => {
                var x: usize = 0;
                while (x < stride) : (x += 1) {
                    const left = if (x >= 4) dest_row[x - 4] else 0;
                    dest_row[x] = src_row[x] +% left;
                }
            },
            2 => {
                var x: usize = 0;
                while (x < stride) : (x += 1) {
                    const up = if (y > 0) pixels[(y - 1) * stride + x] else 0;
                    dest_row[x] = src_row[x] +% up;
                }
            },
            3 => {
                var x: usize = 0;
                while (x < stride) : (x += 1) {
                    const left = if (x >= 4) dest_row[x - 4] else 0;
                    const up = if (y > 0) pixels[(y - 1) * stride + x] else 0;
                    dest_row[x] = src_row[x] +% @as(u8, @intCast(@divTrunc(@as(u16, left) + up, 2)));
                }
            },
            4 => {
                var x: usize = 0;
                while (x < stride) : (x += 1) {
                    const left = if (x >= 4) dest_row[x - 4] else 0;
                    const up = if (y > 0) pixels[(y - 1) * stride + x] else 0;
                    const left_up = if (x >= 4 and y > 0) pixels[(y - 1) * stride + x - 4] else 0;
                    dest_row[x] = src_row[x] +% paethPredictor(left, up, left_up);
                }
            },
            else => return error.InvalidFilterType,
        }
    }

    return PngImage{ .width = width, .height = height, .pixels = pixels };
}
