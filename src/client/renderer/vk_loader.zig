//! vk_loader.zig
//! Runtime Vulkan function loader via SDL3's SDL_Vulkan_GetVkGetInstanceProcAddr.
//!
//! SDL3 ships its own Vulkan loader on every platform (including MoltenVK on
//! macOS), so we never link against libvulkan directly – we only link libSDL3.

const std = @import("std");
const vk = @import("vk_types.zig");

// --------------------------------------------------------------------------
// SDL3 C bindings (only the handful we actually need)
// --------------------------------------------------------------------------
pub const SDL_Window = vk.SDL_Window;

pub extern fn SDL_Init(flags: u32) bool;
pub extern fn SDL_Quit() void;
pub extern fn SDL_CreateWindow(title: [*:0]const u8, w: c_int, h: c_int, flags: u64) ?*SDL_Window;
pub extern fn SDL_DestroyWindow(win: *SDL_Window) void;
pub extern fn SDL_GetError() [*:0]const u8;
pub extern fn SDL_WaitEvent(event: *SDLEvent) bool;
pub extern fn SDL_PollEvent(event: *SDLEvent) bool;
pub extern fn SDL_GetWindowSize(win: *SDL_Window, w: *c_int, h: *c_int) void;
pub extern fn SDL_GetWindowSizeInPixels(win: *SDL_Window, w: *c_int, h: *c_int) bool;
pub extern fn SDL_PumpEvents() void;
pub extern fn SDL_SetHint(name: [*:0]const u8, value: [*:0]const u8) bool;
// Mouse / keyboard
pub extern fn SDL_SetWindowRelativeMouseMode(win: *SDL_Window, enabled: bool) bool;
pub extern fn SDL_GetRelativeMouseState(x: *f32, y: *f32) u32;
pub extern fn SDL_GetKeyboardState(numkeys: *c_int) ?[*]const bool;
// SDL_Scancode
pub const SDL_SCANCODE_W = 26;
pub const SDL_SCANCODE_A = 4;
pub const SDL_SCANCODE_S = 22;
pub const SDL_SCANCODE_D = 7;
pub const SDL_SCANCODE_Q = 20;
pub const SDL_SCANCODE_E = 8;
pub const SDL_SCANCODE_ESCAPE = 41;
pub const SDL_SCANCODE_SPACE = 44;
pub const SDL_SCANCODE_LSHIFT = 225;

// SDL_Vulkan_*
pub extern fn SDL_Vulkan_LoadLibrary(path: ?[*:0]const u8) bool;
pub extern fn SDL_Vulkan_UnloadLibrary() void;
pub extern fn SDL_Vulkan_GetVkGetInstanceProcAddr() ?*const anyopaque;
pub extern fn SDL_Vulkan_GetInstanceExtensions(count: *u32) ?[*][*:0]const u8;
pub extern fn SDL_Vulkan_CreateSurface(win: *SDL_Window, instance: vk.VkInstance, allocator: ?*const anyopaque, surface: *vk.VkSurfaceKHR) bool;

// Minimal SDL event (we only care about quit + window)
// SDL_EventType values (SDL3)
pub const SDL_EVENT_QUIT: u32 = 0x100;
pub const SDL_EVENT_WINDOW_CLOSE_REQUESTED: u32 = 0x223; // red-X on macOS
pub const SDL_EVENT_WINDOW_RESIZED: u32 = 0x205;
pub const SDL_EVENT_KEY_DOWN: u32 = 0x300;
// Legacy alias so existing code compiles
pub const SDL_QUIT = SDL_EVENT_QUIT;

pub const SDL_WINDOW_VULKAN: u64 = 0x0000000010000000;
pub const SDL_INIT_VIDEO: u32 = 0x00000020;

// SDL_Event is a union padded to 128 bytes (confirmed from SDL3 headers).
pub const SDLEvent = extern struct {
    type: u32,
    _pad: [124]u8,
};

// --------------------------------------------------------------------------
// vkCreateInstance – loaded from the SDL Vulkan loader before we have a
// VkInstance (so we cannot use VkFuncs yet).
// --------------------------------------------------------------------------
var _vkCreateInstance: ?*const fn (
    *const vk.VkInstanceCreateInfo,
    ?*const anyopaque,
    *vk.VkInstance,
) callconv(.c) vk.VkResult = null;

var _vkGetInstanceProcAddr: ?*const fn (
    vk.VkInstance,
    [*:0]const u8,
) callconv(.c) ?*const anyopaque = null;

/// Call after SDL_Vulkan_LoadLibrary to prime the two bootstrap functions.
pub fn initLoader() !void {
    const raw = SDL_Vulkan_GetVkGetInstanceProcAddr() orelse
        return error.NoVkGetInstanceProcAddr;
    _vkGetInstanceProcAddr = @ptrCast(@alignCast(raw));

    // vkCreateInstance is loaded with a null instance
    _vkCreateInstance = @ptrCast(@alignCast(
        _vkGetInstanceProcAddr.?(null, "vkCreateInstance") orelse
            return error.NoVkCreateInstance,
    ));
}

/// Create a VkInstance.
pub fn createInstance(info: *const vk.VkInstanceCreateInfo) !vk.VkInstance {
    var inst: vk.VkInstance = null;
    const r = _vkCreateInstance.?(info, null, &inst);
    if (r != vk.VK_SUCCESS) return error.VkCreateInstanceFailed;
    return inst;
}

/// Load ALL device/instance functions we need into a VkFuncs table.
pub fn loadFuncs(instance: vk.VkInstance, device: vk.VkDevice) !vk.VkFuncs {
    const gipa = _vkGetInstanceProcAddr.?;

    // Helper: load an instance-level proc (device may be null during early load)
    const iproc = struct {
        fn get(inst: vk.VkInstance, name: [*:0]const u8) ?*const anyopaque {
            return _vkGetInstanceProcAddr.?(inst, name);
        }
    }.get;

    // For device-level procs we use vkGetDeviceProcAddr once we have a device.
    const gdpa_raw: ?*const anyopaque = iproc(instance, "vkGetDeviceProcAddr");
    const gdpa: *const fn (vk.VkDevice, [*:0]const u8) callconv(.c) ?*const anyopaque =
        @ptrCast(@alignCast(gdpa_raw orelse return error.NoVkGetDeviceProcAddr));

    const dp = struct {
        fn get(dev: vk.VkDevice, gdpa_fn: anytype, name: [*:0]const u8) ?*const anyopaque {
            return gdpa_fn(dev, name);
        }
    }.get;

    _ = gipa; // suppress unused warning

    return .{
        .vkDestroyInstance = @ptrCast(@alignCast(iproc(instance, "vkDestroyInstance") orelse return error.MissingFn)),
        .vkEnumeratePhysicalDevices = @ptrCast(@alignCast(iproc(instance, "vkEnumeratePhysicalDevices") orelse return error.MissingFn)),
        .vkEnumerateDeviceExtensionProperties = @ptrCast(@alignCast(iproc(instance, "vkEnumerateDeviceExtensionProperties") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceProperties = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceProperties") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceQueueFamilyProperties = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceQueueFamilyProperties") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceMemoryProperties = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceMemoryProperties") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceFeatures = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceFeatures") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceSurfaceSupportKHR = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceSurfaceSupportKHR") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceSurfaceCapabilitiesKHR = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceSurfaceFormatsKHR = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceSurfaceFormatsKHR") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceSurfacePresentModesKHR = @ptrCast(@alignCast(iproc(instance, "vkGetPhysicalDeviceSurfacePresentModesKHR") orelse return error.MissingFn)),
        .vkCreateDevice = @ptrCast(@alignCast(iproc(instance, "vkCreateDevice") orelse return error.MissingFn)),
        .vkDestroySurfaceKHR = @ptrCast(@alignCast(iproc(instance, "vkDestroySurfaceKHR") orelse return error.MissingFn)),
        .vkGetDeviceProcAddr = @ptrCast(@alignCast(gdpa_raw orelse return error.MissingFn)),
        .vkDestroyDevice = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyDevice") orelse return error.MissingFn)),
        .vkGetDeviceQueue = @ptrCast(@alignCast(dp(device, gdpa, "vkGetDeviceQueue") orelse return error.MissingFn)),
        .vkCreateSwapchainKHR = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateSwapchainKHR") orelse return error.MissingFn)),
        .vkDestroySwapchainKHR = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroySwapchainKHR") orelse return error.MissingFn)),
        .vkGetSwapchainImagesKHR = @ptrCast(@alignCast(dp(device, gdpa, "vkGetSwapchainImagesKHR") orelse return error.MissingFn)),
        .vkAcquireNextImageKHR = @ptrCast(@alignCast(dp(device, gdpa, "vkAcquireNextImageKHR") orelse return error.MissingFn)),
        .vkQueuePresentKHR = @ptrCast(@alignCast(dp(device, gdpa, "vkQueuePresentKHR") orelse return error.MissingFn)),
        .vkQueueSubmit = @ptrCast(@alignCast(dp(device, gdpa, "vkQueueSubmit") orelse return error.MissingFn)),
        .vkQueueWaitIdle = @ptrCast(@alignCast(dp(device, gdpa, "vkQueueWaitIdle") orelse return error.MissingFn)),
        .vkDeviceWaitIdle = @ptrCast(@alignCast(dp(device, gdpa, "vkDeviceWaitIdle") orelse return error.MissingFn)),
        .vkCreateImageView = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateImageView") orelse return error.MissingFn)),
        .vkDestroyImageView = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyImageView") orelse return error.MissingFn)),
        .vkCreateRenderPass = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateRenderPass") orelse return error.MissingFn)),
        .vkDestroyRenderPass = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyRenderPass") orelse return error.MissingFn)),
        .vkCreateFramebuffer = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateFramebuffer") orelse return error.MissingFn)),
        .vkDestroyFramebuffer = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyFramebuffer") orelse return error.MissingFn)),
        .vkCreateShaderModule = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateShaderModule") orelse return error.MissingFn)),
        .vkDestroyShaderModule = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyShaderModule") orelse return error.MissingFn)),
        .vkCreateDescriptorSetLayout = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateDescriptorSetLayout") orelse return error.MissingFn)),
        .vkDestroyDescriptorSetLayout = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyDescriptorSetLayout") orelse return error.MissingFn)),
        .vkCreateDescriptorPool = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateDescriptorPool") orelse return error.MissingFn)),
        .vkDestroyDescriptorPool = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyDescriptorPool") orelse return error.MissingFn)),
        .vkAllocateDescriptorSets = @ptrCast(@alignCast(dp(device, gdpa, "vkAllocateDescriptorSets") orelse return error.MissingFn)),
        .vkUpdateDescriptorSets = @ptrCast(@alignCast(dp(device, gdpa, "vkUpdateDescriptorSets") orelse return error.MissingFn)),
        .vkCreatePipelineLayout = @ptrCast(@alignCast(dp(device, gdpa, "vkCreatePipelineLayout") orelse return error.MissingFn)),
        .vkDestroyPipelineLayout = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyPipelineLayout") orelse return error.MissingFn)),
        .vkCreateGraphicsPipelines = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateGraphicsPipelines") orelse return error.MissingFn)),
        .vkDestroyPipeline = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyPipeline") orelse return error.MissingFn)),
        .vkCreateCommandPool = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateCommandPool") orelse return error.MissingFn)),
        .vkDestroyCommandPool = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyCommandPool") orelse return error.MissingFn)),
        .vkAllocateCommandBuffers = @ptrCast(@alignCast(dp(device, gdpa, "vkAllocateCommandBuffers") orelse return error.MissingFn)),
        .vkFreeCommandBuffers = @ptrCast(@alignCast(dp(device, gdpa, "vkFreeCommandBuffers") orelse return error.MissingFn)),
        .vkBeginCommandBuffer = @ptrCast(@alignCast(dp(device, gdpa, "vkBeginCommandBuffer") orelse return error.MissingFn)),
        .vkEndCommandBuffer = @ptrCast(@alignCast(dp(device, gdpa, "vkEndCommandBuffer") orelse return error.MissingFn)),
        .vkCmdBeginRenderPass = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdBeginRenderPass") orelse return error.MissingFn)),
        .vkCmdEndRenderPass = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdEndRenderPass") orelse return error.MissingFn)),
        .vkCmdBindPipeline = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdBindPipeline") orelse return error.MissingFn)),
        .vkCmdBindVertexBuffers = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdBindVertexBuffers") orelse return error.MissingFn)),
        .vkCmdBindDescriptorSets = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdBindDescriptorSets") orelse return error.MissingFn)),
        .vkCmdDraw = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdDraw") orelse return error.MissingFn)),
        .vkCmdSetViewport = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdSetViewport") orelse return error.MissingFn)),
        .vkCmdSetScissor = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdSetScissor") orelse return error.MissingFn)),
        .vkCmdPipelineBarrier = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdPipelineBarrier") orelse return error.MissingFn)),
        .vkCmdCopyBufferToImage = @ptrCast(@alignCast(dp(device, gdpa, "vkCmdCopyBufferToImage") orelse return error.MissingFn)),
        .vkCreateFence = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateFence") orelse return error.MissingFn)),
        .vkDestroyFence = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyFence") orelse return error.MissingFn)),
        .vkWaitForFences = @ptrCast(@alignCast(dp(device, gdpa, "vkWaitForFences") orelse return error.MissingFn)),
        .vkResetFences = @ptrCast(@alignCast(dp(device, gdpa, "vkResetFences") orelse return error.MissingFn)),
        .vkCreateSemaphore = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateSemaphore") orelse return error.MissingFn)),
        .vkDestroySemaphore = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroySemaphore") orelse return error.MissingFn)),
        .vkCreateBuffer = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateBuffer") orelse return error.MissingFn)),
        .vkDestroyBuffer = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyBuffer") orelse return error.MissingFn)),
        .vkGetBufferMemoryRequirements = @ptrCast(@alignCast(dp(device, gdpa, "vkGetBufferMemoryRequirements") orelse return error.MissingFn)),
        .vkAllocateMemory = @ptrCast(@alignCast(dp(device, gdpa, "vkAllocateMemory") orelse return error.MissingFn)),
        .vkFreeMemory = @ptrCast(@alignCast(dp(device, gdpa, "vkFreeMemory") orelse return error.MissingFn)),
        .vkBindBufferMemory = @ptrCast(@alignCast(dp(device, gdpa, "vkBindBufferMemory") orelse return error.MissingFn)),
        .vkMapMemory = @ptrCast(@alignCast(dp(device, gdpa, "vkMapMemory") orelse return error.MissingFn)),
        .vkUnmapMemory = @ptrCast(@alignCast(dp(device, gdpa, "vkUnmapMemory") orelse return error.MissingFn)),
        .vkCreateImage = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateImage") orelse return error.MissingFn)),
        .vkDestroyImage = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroyImage") orelse return error.MissingFn)),
        .vkGetImageMemoryRequirements = @ptrCast(@alignCast(dp(device, gdpa, "vkGetImageMemoryRequirements") orelse return error.MissingFn)),
        .vkBindImageMemory = @ptrCast(@alignCast(dp(device, gdpa, "vkBindImageMemory") orelse return error.MissingFn)),
        .vkCreateSampler = @ptrCast(@alignCast(dp(device, gdpa, "vkCreateSampler") orelse return error.MissingFn)),
        .vkDestroySampler = @ptrCast(@alignCast(dp(device, gdpa, "vkDestroySampler") orelse return error.MissingFn)),
        .vkResetCommandPool = @ptrCast(@alignCast(dp(device, gdpa, "vkResetCommandPool") orelse return error.MissingFn)),
    };
}
