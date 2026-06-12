//! gpu_buffer.zig
//! Managed GPU vertex buffer – wraps a VkBuffer+VkDeviceMemory pair that is
//! host-visible (mapped persistently) so we can update it every frame without
//! a staging buffer.
//!
//! For chunk geometry we use a separate static GpuBuffer per chunk layer
//! (uploaded once then re-used), which matches the C++ VBO approach.

const std = @import("std");
const vk = @import("vk_types.zig");
const ctx_mod = @import("vk_context.zig");

pub const GpuBuffer = struct {
    buf: vk.VkBuffer,
    mem: vk.VkDeviceMemory,
    capacity: vk.VkDeviceSize, // bytes allocated
    vertex_count: u32, // vertices currently stored

    /// Allocate a host-visible buffer of `byte_capacity` bytes with given usage flags.
    pub fn init(
        context: *ctx_mod.VkContext,
        byte_capacity: vk.VkDeviceSize,
        usage: vk.VkBufferUsageFlagBits,
    ) !GpuBuffer {
        var buf: vk.VkBuffer = 0;
        var mem: vk.VkDeviceMemory = 0;
        try context.createBuffer(
            byte_capacity,
            usage,
            vk.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | vk.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
            &buf,
            &mem,
        );
        return .{
            .buf = buf,
            .mem = mem,
            .capacity = byte_capacity,
            .vertex_count = 0,
        };
    }

    pub fn deinit(self: *GpuBuffer, vf: vk.VkFuncs, device: vk.VkDevice) void {
        vf.vkDestroyBuffer(device, self.buf, null);
        vf.vkFreeMemory(device, self.mem, null);
    }

    /// Upload `vertices` bytes.  Returns error if the buffer is too small.
    pub fn upload(self: *GpuBuffer, context: *ctx_mod.VkContext, data: []const u8) !void {
        if (data.len > self.capacity) return error.BufferTooSmall;
        try context.uploadToBuffer(self.mem, data);
        self.vertex_count = @intCast(data.len / @import("tesselator.zig").Vertex);
    }

    /// Upload a single uniform structure configuration safely.
    pub fn uploadUbo(
        self: *GpuBuffer,
        context: *ctx_mod.VkContext,
        ubo_data: anytype,
    ) !void {
        const bytes = std.mem.asBytes(&ubo_data);
        if (bytes.len > self.capacity) return error.BufferTooSmall;
        try context.uploadToBuffer(self.mem, bytes);
    }

    /// Upload typed vertex slice.
    pub fn uploadVertices(
        self: *GpuBuffer,
        context: *ctx_mod.VkContext,
        verts: anytype, // []const Vertex or []const SkyVertex etc.
    ) !void {
        const T = @typeInfo(@TypeOf(verts)).pointer.child;
        const bytes = std.mem.sliceAsBytes(verts);
        if (bytes.len > self.capacity) return error.BufferTooSmall;
        try context.uploadToBuffer(self.mem, bytes);
        self.vertex_count = @intCast(verts.len);
        _ = T;
    }

    pub fn isEmpty(self: *const GpuBuffer) bool {
        return self.vertex_count == 0;
    }
};
