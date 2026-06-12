//! tesselator.zig
//! CPU-side vertex builder – direct port of Tesselator.cpp / Tesselator.h.
//!
//! The C++ version built quads then expanded them to triangle-pairs and
//! uploaded to a VBO.  This Zig version does the same thing: it accumulates
//! Vertex data in a dynamic slice, converts quads→triangles on the fly, and
//! exposes the resulting slice so the caller can upload it into a Vulkan
//! vertex buffer.
//!
//! Coordinate layout (per vertex, 24 bytes, matching the GLSL layout):
//!   location 0 : xyz  (3 × f32 = 12 bytes)
//!   location 1 : uv   (2 × f32 =  8 bytes)
//!   location 2 : color (4 × u8 = 4 bytes, packed ABGR little-endian)

const std = @import("std");

// ---------------------------------------------------------------------------
// Public vertex type – matches terrain.vert attribute layout
// ---------------------------------------------------------------------------
pub const Vertex = extern struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
    /// Packed RGBA, little-endian: byte0=R, byte1=G, byte2=B, byte3=A
    color: u32,
};

comptime {
    std.debug.assert(@sizeOf(Vertex) == 24);
    std.debug.assert(@offsetOf(Vertex, "x") == 0);
    std.debug.assert(@offsetOf(Vertex, "u") == 12);
    std.debug.assert(@offsetOf(Vertex, "color") == 20);
}

pub const MAX_VERTICES: usize = 256 * 1024; // 256 K vertices

pub const Mode = enum { quads, triangles, lines };

pub const Tesselator = struct {
    alloc: std.mem.Allocator,
    verts: std.ArrayListUnmanaged(Vertex),

    // Current state
    ox: f32 = 0,
    oy: f32 = 0,
    oz: f32 = 0,
    cur_u: f32 = 0,
    cur_v: f32 = 0,
    cur_color: u32 = 0xFFFFFFFF, // opaque white
    no_color: bool = false,
    mode: Mode = .quads,
    quad_count: u32 = 0, // vertices emitted in current quad (0-3)
    tesselating: bool = false,
    quad_verts: [4]Vertex = undefined,

    pub fn init(alloc: std.mem.Allocator) !Tesselator {
        return .{
            .alloc = alloc,
            .verts = try std.ArrayListUnmanaged(Vertex).initCapacity(alloc, 4096),
        };
    }

    pub fn deinit(self: *Tesselator) void {
        self.verts.deinit(self.alloc);
    }

    // -----------------------------------------------------------------------
    // Begin / end
    // -----------------------------------------------------------------------
    pub fn begin(self: *Tesselator) void {
        self.beginMode(.quads);
    }

    pub fn beginMode(self: *Tesselator, mode: Mode) void {
        self.verts.clearRetainingCapacity();
        self.quad_count = 0;
        self.no_color = false;
        self.mode = mode;
        self.tesselating = true;
    }

    /// Return the accumulated vertices.  Caller must upload them before the
    /// next begin() call (the slice is invalidated then).
    pub fn finish(self: *Tesselator) []const Vertex {
        self.tesselating = false;
        return self.verts.items;
    }

    // -----------------------------------------------------------------------
    // State setters
    // -----------------------------------------------------------------------
    pub fn offset(self: *Tesselator, x: f32, y: f32, z: f32) void {
        self.ox = x;
        self.oy = y;
        self.oz = z;
    }

    pub fn tex(self: *Tesselator, u: f32, v: f32) void {
        self.cur_u = u;
        self.cur_v = v;
    }

    pub fn noColor(self: *Tesselator) void {
        self.no_color = true;
    }

    pub fn enableColor(self: *Tesselator) void {
        self.no_color = false;
    }

    // color(r, g, b, a) – floats 0..1
    pub fn colorF(self: *Tesselator, r: f32, g: f32, b: f32, a: f32) void {
        self.colorI(
            @intFromFloat(r * 255.0),
            @intFromFloat(g * 255.0),
            @intFromFloat(b * 255.0),
            @intFromFloat(a * 255.0),
        );
    }

    // color(r, g, b, a) – bytes 0..255
    pub fn colorI(self: *Tesselator, r: u8, g: u8, b: u8, a: u8) void {
        if (self.no_color) return;
        // little-endian RGBA packing: byte0=R byte1=G byte2=B byte3=A
        self.cur_color = @as(u32, r) |
            (@as(u32, g) << 8) |
            (@as(u32, b) << 16) |
            (@as(u32, a) << 24);
    }

    pub fn colorRGB(self: *Tesselator, r: u8, g: u8, b: u8) void {
        self.colorI(r, g, b, 255);
    }

    pub fn colorPacked(self: *Tesselator, argb: u32) void {
        if (self.no_color) return;
        const r: u8 = @truncate((argb >> 16) & 0xFF);
        const g: u8 = @truncate((argb >> 8) & 0xFF);
        const b: u8 = @truncate(argb & 0xFF);
        self.colorI(r, g, b, 255);
    }

    // -----------------------------------------------------------------------
    // Vertex emission
    // -----------------------------------------------------------------------

    /// Emit one vertex at (x,y,z) + current uv/color + offset.
    pub fn vertex(self: *Tesselator, x: f32, y: f32, z: f32) void {
        const v = Vertex{
            .x = x + self.ox,
            .y = y + self.oy,
            .z = z + self.oz,
            .u = self.cur_u,
            .v = self.cur_v,
            .color = if (self.no_color) 0xFFFFFFFF else self.cur_color,
        };

        if (self.mode == .quads) {
            self.quad_verts[self.quad_count] = v;
            self.quad_count += 1;
            if (self.quad_count == 4) {
                self.quad_count = 0;
                // Emit 6 vertices for 2 triangles: CCW tri0 (0,1,2) and tri1 (0,2,3)
                self.verts.appendSlice(self.alloc, &.{
                    self.quad_verts[0],
                    self.quad_verts[1],
                    self.quad_verts[2],
                    self.quad_verts[0],
                    self.quad_verts[2],
                    self.quad_verts[3],
                }) catch return;
            }
        } else {
            self.verts.append(self.alloc, v) catch return;
        }
    }

    pub fn vertexUV(self: *Tesselator, x: f32, y: f32, z: f32, u: f32, v: f32) void {
        self.tex(u, v);
        self.vertex(x, y, z);
    }

    // -----------------------------------------------------------------------
    // Vertex count helpers
    // -----------------------------------------------------------------------
    pub fn vertexCount(self: *const Tesselator) u32 {
        return @intCast(self.verts.items.len);
    }
};
