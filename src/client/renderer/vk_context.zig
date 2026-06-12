const config = @import("config");
const std = @import("std");
const vk = @import("vk_types.zig");
const loader = @import("vk_loader.zig");

pub const MAX_FRAMES_IN_FLIGHT: u32 = 3;

/// Per-frame synchronisation objects.
pub const FrameSync = struct {
    image_available: vk.VkSemaphore,
    render_finished: vk.VkSemaphore,
    in_flight: vk.VkFence,
    cmd: vk.VkCommandBuffer,
};

pub const VkContext = struct {
    alloc: std.mem.Allocator,
    vf: vk.VkFuncs,

    instance: vk.VkInstance,
    surface: vk.VkSurfaceKHR,
    physical_device: vk.VkPhysicalDevice,
    device: vk.VkDevice,

    graphics_family: u32,
    graphics_queue: vk.VkQueue,

    swapchain: vk.VkSwapchainKHR,
    swap_format: vk.VkFormat,
    swap_extent: vk.VkExtent2D,
    swap_images: []vk.VkImage,
    swap_views: []vk.VkImageView,

    depth_image: vk.VkImage,
    depth_memory: vk.VkDeviceMemory,
    depth_view: vk.VkImageView,
    depth_format: vk.VkFormat,

    render_pass: vk.VkRenderPass,
    framebuffers: []vk.VkFramebuffer,

    cmd_pool: vk.VkCommandPool,
    frames: [MAX_FRAMES_IN_FLIGHT]FrameSync,
    frame_index: u32,

    mem_props: vk.VkPhysicalDeviceMemoryProperties,

    /// Create the full context from a SDL3 window.
    pub fn init(
        alloc: std.mem.Allocator,
        window: *loader.SDL_Window,
    ) !VkContext {
        try loader.initLoader();

        // ---- 2. Instance ------------------------------------------------
        var ext_count: u32 = 0;
        const raw_exts = loader.SDL_Vulkan_GetInstanceExtensions(&ext_count) orelse
            return error.NoSDLExtensions;

        const app_info = vk.VkApplicationInfo{
            .sType = 0,
            .pApplicationName = "zigcraft",
            .applicationVersion = 1,
            .pEngineName = "zig-vk",
            .engineVersion = 1,
            .apiVersion = vkMakeVersion(1, 2, 0),
        };
        const inst_info = vk.VkInstanceCreateInfo{
            .sType = 1,
            .pApplicationInfo = &app_info,
            .enabledLayerCount = 0,
            .ppEnabledLayerNames = null,
            .enabledExtensionCount = ext_count,
            .ppEnabledExtensionNames = @ptrCast(raw_exts),
        };
        const instance = try loader.createInstance(&inst_info);

        // ---- 3. Surface -------------------------------------------------
        var surface: vk.VkSurfaceKHR = 0;
        if (!loader.SDL_Vulkan_CreateSurface(window, instance, null, &surface))
            return error.SurfaceCreateFailed;

        // ---- 4. Pick physical device ------------------------------------
        const ifn = try loadInstanceFuncs(instance);

        var pd_count: u32 = 0;
        _ = ifn.vkEnumeratePhysicalDevices(instance, &pd_count, null);
        const pds = try alloc.alloc(vk.VkPhysicalDevice, pd_count);
        defer alloc.free(pds);
        _ = ifn.vkEnumeratePhysicalDevices(instance, &pd_count, pds.ptr);

        var chosen_pd: vk.VkPhysicalDevice = null;
        var gfx_family: u32 = 0;
        for (pds) |pd| {
            if (try findGraphicsFamily(ifn, pd, surface, &gfx_family)) {
                chosen_pd = pd;
                break;
            }
        }
        if (chosen_pd == null) return error.NoSuitableGPU;

        // ---- 5. Logical device ------------------------------------------
        const prio: f32 = 1.0;
        const queue_ci = vk.VkDeviceQueueCreateInfo{
            .sType = 2,
            .queueFamilyIndex = gfx_family,
            .queueCount = 1,
            .pQueuePriorities = &prio,
        };

        // Figure out which extensions the physical device supports.
        // VK_KHR_portability_subset is MoltenVK-specific; KosmicKrisp doesn't have it.
        var dev_ext_count: u32 = 0;
        _ = ifn.vkEnumerateDeviceExtensionProperties(chosen_pd, null, &dev_ext_count, null);
        const dev_ext_props = try alloc.alloc(vk.VkExtensionProperties, dev_ext_count);
        defer alloc.free(dev_ext_props);
        _ = ifn.vkEnumerateDeviceExtensionProperties(chosen_pd, null, &dev_ext_count, dev_ext_props.ptr);

        var has_portability = false;
        for (dev_ext_props) |ep| {
            if (std.mem.eql(u8, std.mem.sliceTo(&ep.extensionName, 0), "VK_KHR_portability_subset")) {
                has_portability = true;
                break;
            }
        }

        const PORTABILITY_SUB = "VK_KHR_portability_subset";
        var dev_exts: [2][*:0]const u8 = undefined;
        var dev_ext_count_u: u32 = 1;
        dev_exts[0] = "VK_KHR_swapchain";
        if (has_portability) {
            dev_exts[1] = PORTABILITY_SUB;
            dev_ext_count_u = 2;
        }
        var features: vk.VkPhysicalDeviceFeatures = .{};
        const dev_ci = vk.VkDeviceCreateInfo{
            .sType = 3,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = @as([*]const vk.VkDeviceQueueCreateInfo, @ptrCast(&queue_ci)),
            .enabledExtensionCount = dev_ext_count_u,
            .ppEnabledExtensionNames = &dev_exts,
            .pEnabledFeatures = &features,
        };
        var device: vk.VkDevice = null;
        var r = ifn.vkCreateDevice(chosen_pd, &dev_ci, null, &device);
        if (r != vk.VK_SUCCESS) return error.DeviceCreateFailed;

        // ---- 6. Load full function table --------------------------------
        const vf = try loader.loadFuncs(instance, device);

        var gfx_queue: vk.VkQueue = null;
        vf.vkGetDeviceQueue(device, gfx_family, 0, &gfx_queue);

        // Memory properties
        var mem_props: vk.VkPhysicalDeviceMemoryProperties = undefined;
        vf.vkGetPhysicalDeviceMemoryProperties(chosen_pd, &mem_props);

        // ---- 7. Swapchain -----------------------------------------------
        var caps: vk.VkSurfaceCapabilitiesKHR = undefined;
        _ = vf.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(chosen_pd, surface, &caps);

        const swap_format = try chooseSurfaceFormat(alloc, vf, chosen_pd, surface);
        const present_mode = try choosePresentMode(alloc, vf, chosen_pd, surface);

        // Use pixel size (not logical size) so Retina displays work correctly.
        var win_w: c_int = 0;
        var win_h: c_int = 0;
        _ = loader.SDL_GetWindowSizeInPixels(window, &win_w, &win_h);
        const swap_extent = chooseExtent(caps, @intCast(win_w), @intCast(win_h));

        var img_count = caps.minImageCount + 1;
        if (caps.maxImageCount > 0 and img_count > caps.maxImageCount)
            img_count = caps.maxImageCount;

        const sc_ci = vk.VkSwapchainCreateInfoKHR{
            .sType = 1000001000,
            .surface = surface,
            .minImageCount = img_count,
            .imageFormat = swap_format.format,
            .imageColorSpace = swap_format.colorSpace,
            .imageExtent = swap_extent,
            .imageUsage = vk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
            .preTransform = caps.currentTransform,
            .compositeAlpha = 0x00000001, // VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR
            .presentMode = present_mode,
        };
        var swapchain: vk.VkSwapchainKHR = 0;
        r = vf.vkCreateSwapchainKHR(device, &sc_ci, null, &swapchain);
        if (r != vk.VK_SUCCESS) return error.SwapchainCreateFailed;

        // Swapchain images + views
        var sc_img_count: u32 = 0;
        _ = vf.vkGetSwapchainImagesKHR(device, swapchain, &sc_img_count, null);
        const swap_images = try alloc.alloc(vk.VkImage, sc_img_count);
        _ = vf.vkGetSwapchainImagesKHR(device, swapchain, &sc_img_count, swap_images.ptr);

        const swap_views = try alloc.alloc(vk.VkImageView, sc_img_count);
        for (swap_images, 0..) |img, i| {
            swap_views[i] = try createImageView(vf, device, img, swap_format.format, vk.VK_IMAGE_ASPECT_COLOR_BIT);
        }

        // ---- 8. Depth image -------------------------------------------
        const depth_fmt = vk.VK_FORMAT_D32_SFLOAT;
        var depth_image: vk.VkImage = 0;
        var depth_memory: vk.VkDeviceMemory = 0;
        try createImage(vf, device, mem_props, swap_extent.width, swap_extent.height, depth_fmt, vk.VK_IMAGE_TILING_OPTIMAL, vk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT, vk.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, &depth_image, &depth_memory);
        const depth_view = try createImageView(vf, device, depth_image, depth_fmt, vk.VK_IMAGE_ASPECT_DEPTH_BIT);

        // ---- 9. Render pass -------------------------------------------
        const rp = try createMainRenderPass(vf, device, swap_format.format, depth_fmt);

        // ---- 10. Framebuffers ----------------------------------------
        const framebuffers = try alloc.alloc(vk.VkFramebuffer, sc_img_count);
        for (swap_views, 0..) |sv, i| {
            const attachments = [_]vk.VkImageView{ sv, depth_view };
            const fb_ci = vk.VkFramebufferCreateInfo{
                .sType = 37,
                .renderPass = rp,
                .attachmentCount = attachments.len,
                .pAttachments = &attachments,
                .width = swap_extent.width,
                .height = swap_extent.height,
            };
            r = vf.vkCreateFramebuffer(device, &fb_ci, null, &framebuffers[i]);
            if (r != vk.VK_SUCCESS) return error.FramebufferCreateFailed;
        }

        // ---- 11. Command pool + per-frame resources ------------------
        const cp_ci = vk.VkCommandPoolCreateInfo{
            .sType = 39,
            .flags = 0x00000002, // VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
            .queueFamilyIndex = gfx_family,
        };
        var cmd_pool: vk.VkCommandPool = 0;
        r = vf.vkCreateCommandPool(device, &cp_ci, null, &cmd_pool);
        if (r != vk.VK_SUCCESS) return error.CmdPoolCreateFailed;

        var cb_bufs: [MAX_FRAMES_IN_FLIGHT]vk.VkCommandBuffer = undefined;
        const cb_ai = vk.VkCommandBufferAllocateInfo{
            .sType = 40,
            .commandPool = cmd_pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = MAX_FRAMES_IN_FLIGHT,
        };
        r = vf.vkAllocateCommandBuffers(device, &cb_ai, &cb_bufs);
        if (r != vk.VK_SUCCESS) return error.CmdBufAllocFailed;

        var frames: [MAX_FRAMES_IN_FLIGHT]FrameSync = undefined;
        for (&frames, 0..) |*f, i| {
            const sem_ci = vk.VkSemaphoreCreateInfo{ .sType = 9 };
            const fen_ci = vk.VkFenceCreateInfo{ .sType = 8, .flags = vk.VK_FENCE_CREATE_SIGNALED_BIT };
            r = vf.vkCreateSemaphore(device, &sem_ci, null, &f.image_available);
            if (r != vk.VK_SUCCESS) return error.SemCreateFailed;
            r = vf.vkCreateSemaphore(device, &sem_ci, null, &f.render_finished);
            if (r != vk.VK_SUCCESS) return error.SemCreateFailed;
            r = vf.vkCreateFence(device, &fen_ci, null, &f.in_flight);
            if (r != vk.VK_SUCCESS) return error.FenceCreateFailed;
            f.cmd = cb_bufs[i];
        }

        return .{
            .alloc = alloc,
            .vf = vf,
            .instance = instance,
            .surface = surface,
            .physical_device = chosen_pd,
            .device = device,
            .graphics_family = gfx_family,
            .graphics_queue = gfx_queue,
            .swapchain = swapchain,
            .swap_format = swap_format.format,
            .swap_extent = swap_extent,
            .swap_images = swap_images,
            .swap_views = swap_views,
            .depth_image = depth_image,
            .depth_memory = depth_memory,
            .depth_view = depth_view,
            .depth_format = depth_fmt,
            .render_pass = rp,
            .framebuffers = framebuffers,
            .cmd_pool = cmd_pool,
            .frames = frames,
            .frame_index = 0,
            .mem_props = mem_props,
        };
    }

    pub fn deinit(self: *VkContext) void {
        _ = self.vf.vkDeviceWaitIdle(self.device);

        for (&self.frames) |*f| {
            self.vf.vkDestroySemaphore(self.device, f.image_available, null);
            self.vf.vkDestroySemaphore(self.device, f.render_finished, null);
            self.vf.vkDestroyFence(self.device, f.in_flight, null);
        }
        self.vf.vkDestroyCommandPool(self.device, self.cmd_pool, null);

        for (self.framebuffers) |fb| self.vf.vkDestroyFramebuffer(self.device, fb, null);
        self.alloc.free(self.framebuffers);

        self.vf.vkDestroyRenderPass(self.device, self.render_pass, null);

        self.vf.vkDestroyImageView(self.device, self.depth_view, null);
        self.vf.vkDestroyImage(self.device, self.depth_image, null);
        self.vf.vkFreeMemory(self.device, self.depth_memory, null);

        for (self.swap_views) |v| self.vf.vkDestroyImageView(self.device, v, null);
        self.alloc.free(self.swap_views);
        self.alloc.free(self.swap_images);

        self.vf.vkDestroySwapchainKHR(self.device, self.swapchain, null);
        self.vf.vkDestroyDevice(self.device, null);
        self.vf.vkDestroySurfaceKHR(self.instance, self.surface, null);
        self.vf.vkDestroyInstance(self.instance, null);
        loader.SDL_Vulkan_UnloadLibrary();
    }

    /// Advance to next frame slot, wait for in-flight fence.
    pub fn beginFrame(self: *VkContext) !u32 {
        const f = &self.frames[self.frame_index];
        _ = self.vf.vkWaitForFences(self.device, 1, &[_]vk.VkFence{f.in_flight}, 1, std.math.maxInt(u64));

        var image_index: u32 = 0;
        const r = self.vf.vkAcquireNextImageKHR(
            self.device,
            self.swapchain,
            std.math.maxInt(u64),
            f.image_available,
            0,
            &image_index,
        );
        if (r == vk.VK_ERROR_OUT_OF_DATE_KHR) return error.SwapchainOutOfDate;
        if (r != vk.VK_SUCCESS and r != vk.VK_SUBOPTIMAL_KHR) return error.AcquireFailed;

        _ = self.vf.vkResetFences(self.device, 1, &[_]vk.VkFence{f.in_flight});
        return image_index;
    }

    pub fn endFrame(self: *VkContext, image_index: u32) !void {
        const f = &self.frames[self.frame_index];

        const wait_stages = [_]u32{vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
        const submit = vk.VkSubmitInfo{
            .sType = 4,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &[_]vk.VkSemaphore{f.image_available},
            .pWaitDstStageMask = &wait_stages,
            .commandBufferCount = 1,
            .pCommandBuffers = &[_]vk.VkCommandBuffer{f.cmd},
            .signalSemaphoreCount = 1,
            .pSignalSemaphores = &[_]vk.VkSemaphore{f.render_finished},
        };
        var r = self.vf.vkQueueSubmit(self.graphics_queue, 1, &submit, f.in_flight);
        if (r != vk.VK_SUCCESS) return error.SubmitFailed;

        const present = vk.VkPresentInfoKHR{
            .sType = 1000001001,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &[_]vk.VkSemaphore{f.render_finished},
            .swapchainCount = 1,
            .pSwapchains = &[_]vk.VkSwapchainKHR{self.swapchain},
            .pImageIndices = &[_]u32{image_index},
        };
        r = self.vf.vkQueuePresentKHR(self.graphics_queue, &present);
        if (r == vk.VK_ERROR_OUT_OF_DATE_KHR or r == vk.VK_SUBOPTIMAL_KHR)
            return error.SwapchainOutOfDate;
        if (r != vk.VK_SUCCESS) return error.PresentFailed;

        self.frame_index = (self.frame_index + 1) % MAX_FRAMES_IN_FLIGHT;
    }

    /// Allocate + begin a one-shot command buffer for uploads.
    pub fn beginOneShot(self: *VkContext) !vk.VkCommandBuffer {
        var cb: vk.VkCommandBuffer = null;
        const ai = vk.VkCommandBufferAllocateInfo{
            .sType = 40,
            .commandPool = self.cmd_pool,
            .level = vk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
            .commandBufferCount = 1,
        };
        var r = self.vf.vkAllocateCommandBuffers(self.device, &ai, @as([*]vk.VkCommandBuffer, @ptrCast(&cb)));
        if (r != vk.VK_SUCCESS) return error.CmdBufAllocFailed;
        const bi = vk.VkCommandBufferBeginInfo{
            .sType = 42,
            .flags = vk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
        };
        r = self.vf.vkBeginCommandBuffer(cb, &bi);
        if (r != vk.VK_SUCCESS) return error.BeginCmdBufFailed;
        return cb;
    }

    pub fn endOneShot(self: *VkContext, cb: vk.VkCommandBuffer) !void {
        _ = self.vf.vkEndCommandBuffer(cb);
        const submit = vk.VkSubmitInfo{
            .sType = 4,
            .waitSemaphoreCount = 0,
            .pWaitSemaphores = null,
            .pWaitDstStageMask = null,
            .commandBufferCount = 1,
            .pCommandBuffers = &[_]vk.VkCommandBuffer{cb},
            .signalSemaphoreCount = 0,
            .pSignalSemaphores = null,
        };
        _ = self.vf.vkQueueSubmit(self.graphics_queue, 1, &submit, 0);
        _ = self.vf.vkQueueWaitIdle(self.graphics_queue);
        self.vf.vkFreeCommandBuffers(self.device, self.cmd_pool, 1, &[_]vk.VkCommandBuffer{cb});
    }

    /// Find a memory type index matching required bits + properties.
    pub fn findMemoryType(self: *const VkContext, type_bits: u32, props: u32) !u32 {
        var i: u32 = 0;
        while (i < self.mem_props.memoryTypeCount) : (i += 1) {
            if ((type_bits & (@as(u32, 1) << @intCast(i))) != 0 and
                (self.mem_props.memoryTypes[i].propertyFlags & props) == props)
                return i;
        }
        return error.NoSuitableMemoryType;
    }

    /// Create a VkBuffer with memory.
    pub fn createBuffer(
        self: *VkContext,
        size: vk.VkDeviceSize,
        usage: u32,
        mem_flags: u32,
        buf: *vk.VkBuffer,
        mem: *vk.VkDeviceMemory,
    ) !void {
        const ci = vk.VkBufferCreateInfo{
            .sType = 12,
            .size = size,
            .usage = usage,
            .sharingMode = vk.VK_SHARING_MODE_EXCLUSIVE,
        };
        var r = self.vf.vkCreateBuffer(self.device, &ci, null, buf);
        if (r != vk.VK_SUCCESS) return error.BufferCreateFailed;

        var reqs: vk.VkMemoryRequirements = undefined;
        self.vf.vkGetBufferMemoryRequirements(self.device, buf.*, &reqs);

        const ai = vk.VkMemoryAllocateInfo{
            .sType = 5,
            .allocationSize = reqs.size,
            .memoryTypeIndex = try self.findMemoryType(reqs.memoryTypeBits, mem_flags),
        };
        r = self.vf.vkAllocateMemory(self.device, &ai, null, mem);
        if (r != vk.VK_SUCCESS) return error.MemAllocFailed;
        _ = self.vf.vkBindBufferMemory(self.device, buf.*, mem.*, 0);
    }

    /// Upload bytes into a host-visible buffer (no staging).
    pub fn uploadToBuffer(
        self: *VkContext,
        buf_mem: vk.VkDeviceMemory,
        data: []const u8,
    ) !void {
        var mapped: ?*anyopaque = null;
        _ = self.vf.vkMapMemory(self.device, buf_mem, 0, data.len, 0, &mapped);
        @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..data.len], data);
        self.vf.vkUnmapMemory(self.device, buf_mem);
    }

    pub fn currentCmd(self: *VkContext) vk.VkCommandBuffer {
        return self.frames[self.frame_index].cmd;
    }
};

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Subset of VkFuncs needed before we have a VkDevice.
/// We load only the six instance-level procs required for physical device
/// selection and device creation, avoiding the catch-22 of needing a device
/// to load device procs.
const InstanceFuncs = struct {
    vkEnumeratePhysicalDevices: *const fn (vk.VkInstance, *u32, ?[*]vk.VkPhysicalDevice) callconv(.c) vk.VkResult,
    vkEnumerateDeviceExtensionProperties: *const fn (vk.VkPhysicalDevice, ?[*:0]const u8, *u32, ?[*]vk.VkExtensionProperties) callconv(.c) vk.VkResult,
    vkGetPhysicalDeviceQueueFamilyProperties: *const fn (vk.VkPhysicalDevice, *u32, ?[*]vk.VkQueueFamilyProperties) callconv(.c) void,
    vkGetPhysicalDeviceSurfaceSupportKHR: *const fn (vk.VkPhysicalDevice, u32, vk.VkSurfaceKHR, *u32) callconv(.c) vk.VkResult,
    vkCreateDevice: *const fn (vk.VkPhysicalDevice, *const vk.VkDeviceCreateInfo, ?*const anyopaque, *vk.VkDevice) callconv(.c) vk.VkResult,
};

fn loadInstanceFuncs(instance: vk.VkInstance) !InstanceFuncs {
    const raw = loader.SDL_Vulkan_GetVkGetInstanceProcAddr() orelse return error.NoGIPA;
    const gipa: *const fn (vk.VkInstance, [*:0]const u8) callconv(.c) ?*const anyopaque =
        @ptrCast(@alignCast(raw));
    return .{
        .vkEnumeratePhysicalDevices = @ptrCast(@alignCast(gipa(instance, "vkEnumeratePhysicalDevices") orelse return error.MissingFn)),
        .vkEnumerateDeviceExtensionProperties = @ptrCast(@alignCast(gipa(instance, "vkEnumerateDeviceExtensionProperties") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceQueueFamilyProperties = @ptrCast(@alignCast(gipa(instance, "vkGetPhysicalDeviceQueueFamilyProperties") orelse return error.MissingFn)),
        .vkGetPhysicalDeviceSurfaceSupportKHR = @ptrCast(@alignCast(gipa(instance, "vkGetPhysicalDeviceSurfaceSupportKHR") orelse return error.MissingFn)),
        .vkCreateDevice = @ptrCast(@alignCast(gipa(instance, "vkCreateDevice") orelse return error.MissingFn)),
    };
}

fn findGraphicsFamily(
    ifn: InstanceFuncs,
    pd: vk.VkPhysicalDevice,
    surface: vk.VkSurfaceKHR,
    out_family: *u32,
) !bool {
    var count: u32 = 0;
    ifn.vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, null);
    var props_buf: [32]vk.VkQueueFamilyProperties = undefined;
    if (count > 32) count = 32;
    ifn.vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, &props_buf);

    for (props_buf[0..count], 0..) |qf, i| {
        if ((qf.queueFlags & vk.VK_QUEUE_GRAPHICS_BIT) == 0) continue;
        var present_support: u32 = 0;
        _ = ifn.vkGetPhysicalDeviceSurfaceSupportKHR(pd, @intCast(i), surface, &present_support);
        if (present_support != 0) {
            out_family.* = @intCast(i);
            return true;
        }
    }
    return false;
}

fn chooseSurfaceFormat(
    alloc: std.mem.Allocator,
    vf: vk.VkFuncs,
    pd: vk.VkPhysicalDevice,
    surface: vk.VkSurfaceKHR,
) !vk.VkSurfaceFormatKHR {
    var count: u32 = 0;
    _ = vf.vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &count, null);
    const fmts = try alloc.alloc(vk.VkSurfaceFormatKHR, count);
    defer alloc.free(fmts);
    _ = vf.vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &count, fmts.ptr);

    for (fmts) |f| {
        if (f.format == vk.VK_FORMAT_B8G8R8A8_SRGB and
            f.colorSpace == vk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            return f;
    }
    return fmts[0];
}

fn choosePresentMode(
    alloc: std.mem.Allocator,
    vf: vk.VkFuncs,
    pd: vk.VkPhysicalDevice,
    surface: vk.VkSurfaceKHR,
) !vk.VkPresentModeKHR {
    var count: u32 = 0;
    _ = vf.vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &count, null);
    const modes = try alloc.alloc(vk.VkPresentModeKHR, count);
    defer alloc.free(modes);
    _ = vf.vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &count, modes.ptr);
    for (modes) |m| if (m == vk.VK_PRESENT_MODE_MAILBOX_KHR) return m;
    return vk.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseExtent(caps: vk.VkSurfaceCapabilitiesKHR, w: u32, h: u32) vk.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32))
        return caps.currentExtent;
    return .{
        .width = std.math.clamp(w, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(h, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}

pub fn createImageView(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    image: vk.VkImage,
    format: vk.VkFormat,
    aspect: u32,
) !vk.VkImageView {
    const ci = vk.VkImageViewCreateInfo{
        .sType = 15,
        .image = image,
        .viewType = vk.VK_IMAGE_VIEW_TYPE_2D,
        .format = format,
        .components = .{},
        .subresourceRange = .{ .aspectMask = aspect },
    };
    var view: vk.VkImageView = 0;
    const r = vf.vkCreateImageView(device, &ci, null, &view);
    if (r != vk.VK_SUCCESS) return error.ImageViewCreateFailed;
    return view;
}

pub fn createImage(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    mem_props: vk.VkPhysicalDeviceMemoryProperties,
    width: u32,
    height: u32,
    format: vk.VkFormat,
    tiling: vk.VkImageTiling,
    usage: u32,
    mem_flags: u32,
    image: *vk.VkImage,
    memory: *vk.VkDeviceMemory,
) !void {
    const ci = vk.VkImageCreateInfo{
        .sType = 14,
        .imageType = vk.VK_IMAGE_TYPE_2D,
        .format = format,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .tiling = tiling,
        .usage = usage,
    };
    var r = vf.vkCreateImage(device, &ci, null, image);
    if (r != vk.VK_SUCCESS) return error.ImageCreateFailed;

    var reqs: vk.VkMemoryRequirements = undefined;
    vf.vkGetImageMemoryRequirements(device, image.*, &reqs);

    const mem_type = blk: {
        var i: u32 = 0;
        while (i < mem_props.memoryTypeCount) : (i += 1) {
            if ((reqs.memoryTypeBits & (@as(u32, 1) << @intCast(i))) != 0 and
                (mem_props.memoryTypes[i].propertyFlags & mem_flags) == mem_flags)
                break :blk i;
        }
        return error.NoSuitableMemoryType;
    };

    const ai = vk.VkMemoryAllocateInfo{
        .sType = 5,
        .allocationSize = reqs.size,
        .memoryTypeIndex = mem_type,
    };
    r = vf.vkAllocateMemory(device, &ai, null, memory);
    if (r != vk.VK_SUCCESS) return error.MemAllocFailed;
    _ = vf.vkBindImageMemory(device, image.*, memory.*, 0);
}

fn createMainRenderPass(
    vf: vk.VkFuncs,
    device: vk.VkDevice,
    color_fmt: vk.VkFormat,
    depth_fmt: vk.VkFormat,
) !vk.VkRenderPass {
    const attachments = [_]vk.VkAttachmentDescription{
        // colour
        .{
            .format = color_fmt,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_STORE,
            .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = vk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        },
        // depth
        .{
            .format = depth_fmt,
            .samples = vk.VK_SAMPLE_COUNT_1_BIT,
            .loadOp = vk.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .stencilLoadOp = vk.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
            .stencilStoreOp = vk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
            .initialLayout = vk.VK_IMAGE_LAYOUT_UNDEFINED,
            .finalLayout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        },
    };
    const color_ref = vk.VkAttachmentReference{
        .attachment = 0,
        .layout = vk.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };
    const depth_ref = vk.VkAttachmentReference{
        .attachment = 1,
        .layout = vk.VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    };
    const subpass = vk.VkSubpassDescription{
        .pipelineBindPoint = vk.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .colorAttachmentCount = 1,
        .pColorAttachments = @as([*]const vk.VkAttachmentReference, @ptrCast(&color_ref)),
        .pDepthStencilAttachment = &depth_ref,
    };
    const dep = vk.VkSubpassDependency{
        .srcSubpass = vk.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = vk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = vk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    };
    const ci = vk.VkRenderPassCreateInfo{
        .sType = 38,
        .attachmentCount = attachments.len,
        .pAttachments = &attachments,
        .subpassCount = 1,
        .pSubpasses = @as([*]const vk.VkSubpassDescription, @ptrCast(&subpass)),
        .dependencyCount = 1,
        .pDependencies = @as([*]const vk.VkSubpassDependency, @ptrCast(&dep)),
    };
    var rp: vk.VkRenderPass = 0;
    const r = vf.vkCreateRenderPass(device, &ci, null, &rp);
    if (r != vk.VK_SUCCESS) return error.RenderPassCreateFailed;
    return rp;
}

fn vkMakeVersion(major: u32, minor: u32, patch: u32) u32 {
    return (major << 22) | (minor << 12) | patch;
}
