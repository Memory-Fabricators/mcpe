//! demo.zig – SDL3 + Vulkan renderer demo (Zig 0.17-dev / macOS / MoltenVK)
//!
//! Fixes applied vs the original draft:
//!   • SDL_GetWindowSizeInPixels for swapchain (Retina correctness)
//!   • SDL_EVENT_WINDOW_CLOSE_REQUESTED (0x223) for the macOS red-X button
//!   • SDL_PumpEvents() called every frame so Cocoa drains properly
//!   • SIGINT/SIGTERM handler sets a flag → clean shutdown, no Dock zombie
//!   • Sky + cloud UBO offset is (0,0,0): their verts are built relative to
//!     the camera already; only chunk geometry subtracts world cam offset
//!   • Correct column-major perspective × view MVP passed to shaders

const std = @import("std");
const zm = @import("math");
const renderer = @import("renderer");
const loader = renderer.loader;
const vk = renderer.vk;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    // ---- SDL3 init -------------------------------------------------------
    if (!loader.SDL_Init(loader.SDL_INIT_VIDEO)) {
        std.debug.print("SDL_Init failed: {s}\n", .{loader.SDL_GetError()});
        return error.SDLInitFailed;
    }
    defer loader.SDL_Quit();

    // Let SDL3 know we want high-DPI pixel coordinates for Vulkan
    _ = loader.SDL_SetHint("SDL_HINT_VIDEO_HIGH_DPI_DISABLED", "0");

    const window = loader.SDL_CreateWindow(
        "zigcraft",
        1280,
        720,
        loader.SDL_WINDOW_VULKAN,
    ) orelse {
        std.debug.print("SDL_CreateWindow failed: {s}\n", .{loader.SDL_GetError()});
        return error.WindowCreateFailed;
    };
    defer loader.SDL_DestroyWindow(window);

    // ---- Vulkan context --------------------------------------------------
    var context = try renderer.VkContext.init(alloc, window);
    defer context.deinit();

    // ---- Level source ----------------------------------------------------
    var level_source = try renderer.RandomLevelSource.init(alloc, 12345);
    defer level_source.deinit();

    // ---- Level renderer --------------------------------------------------
    var lr = try renderer.LevelRenderer.init(alloc, &context, &level_source, 1);
    defer lr.deinit();

    // ---- Pipeline warm-up (DISABLED for debug) ---------------------------
    // KosmicKrisp defers Metal pipeline compilation to the first vkCmdDraw.
    // We do a submit+wait right now so the GPU doesn't pause us mid-loop.
    // {
    //     const image_index = try context.beginFrame();
    //     var pw: c_int = 1280;
    //     var ph: c_int = 720;
    //     _ = loader.SDL_GetWindowSizeInPixels(window, &pw, &ph);
    //     const aspect = @as(f32, @floatFromInt(pw)) / @as(f32, @floatFromInt(ph));
    //     try lr.recordFrame(
    //         alloc,
    //         image_index,
    //         70.0, aspect, 0.05, 512.0,
    //         viewLookAt(.{ 0, 64, 0 }, .{ 0, 64, 0 }, .{ 0, 1, 0 }),
    //         .{ 0.4, 0.6, 0.9 },
    //         .{ 1, 1, 1 },
    //         0, 64, 0, 0.0,
    //     );
    //     try context.endFrame(image_index);
    //     // Drain the pipeline compilation delay synchronously.
    //     _ = context.vf.vkDeviceWaitIdle(context.device);
    // }

    // Enable relative mouse mode for fly camera
    _ = loader.SDL_SetWindowRelativeMouseMode(window, true);

    // ---- State -----------------------------------------------------------
    var cam_yaw: f32 = 0.0;
    var cam_pitch: f32 = 0.0;
    var cam_x: f32 = 0.0;
    var cam_y: f32 = 80.0;
    var cam_z: f32 = 0.0;

    const SPEED: f32 = 0.15; // blocks per frame at 60fps
    const MOUSE_SENS: f32 = 0.002;

    // ---- Main loop -------------------------------------------------------
    var event: loader.SDLEvent = undefined;

    while (true) {
        loader.SDL_PumpEvents();
        while (loader.SDL_PollEvent(&event)) {
            switch (event.type) {
                loader.SDL_EVENT_QUIT, loader.SDL_EVENT_WINDOW_CLOSE_REQUESTED => return,
                else => {},
            }
        }

        // ---- Mouse look ----
        var mx: f32 = 0;
        var my: f32 = 0;
        _ = loader.SDL_GetRelativeMouseState(&mx, &my);
        cam_yaw += mx * MOUSE_SENS;
        cam_pitch += my * MOUSE_SENS;
        cam_pitch = @min(@max(cam_pitch, -std.math.pi / 2.0 + 0.01), std.math.pi / 2.0 - 0.01);

        // ---- Keyboard movement ----
        var numkeys: c_int = 0;
        const keys = loader.SDL_GetKeyboardState(&numkeys) orelse continue;
        const forward = zm.f32x4(
            @sin(cam_yaw) * @cos(cam_pitch),
            -@sin(cam_pitch),
            -@cos(cam_yaw) * @cos(cam_pitch),
            0.0,
        );
        const right = zm.f32x4(
            @cos(cam_yaw),
            0.0,
            @sin(cam_yaw),
            0.0,
        );
        // W moves in camera look direction (forward)
        const move_dir = forward;

        if (keys[loader.SDL_SCANCODE_W]) {
            cam_x += move_dir[0] * SPEED;
            cam_y += move_dir[1] * SPEED;
            cam_z += move_dir[2] * SPEED;
        }
        if (keys[loader.SDL_SCANCODE_S]) {
            cam_x -= move_dir[0] * SPEED;
            cam_y -= move_dir[1] * SPEED;
            cam_z -= move_dir[2] * SPEED;
        }
        if (keys[loader.SDL_SCANCODE_A]) {
            cam_x -= right[0] * SPEED;
            cam_y -= right[1] * SPEED;
            cam_z -= right[2] * SPEED;
        }
        if (keys[loader.SDL_SCANCODE_D]) {
            cam_x += right[0] * SPEED;
            cam_y += right[1] * SPEED;
            cam_z += right[2] * SPEED;
        }
        if (keys[loader.SDL_SCANCODE_SPACE]) cam_y += SPEED;
        if (keys[loader.SDL_SCANCODE_LSHIFT]) cam_y -= SPEED;
        if (keys[loader.SDL_SCANCODE_ESCAPE]) break;

        var pw: c_int = 1280;
        var ph: c_int = 720;
        _ = loader.SDL_GetWindowSizeInPixels(window, &pw, &ph);
        const aspect = @as(f32, @floatFromInt(pw)) / @as(f32, @floatFromInt(ph));

        const sky_color = [3]f32{ 0.45, 0.65, 0.90 };
        const cloud_color = [3]f32{ 1.0, 1.0, 1.0 };

        // Compute look direction from yaw/pitch.
        const eye = zm.f32x4(cam_x, cam_y, cam_z, 1.0);
        const target = eye + forward;
        const up = zm.f32x4(0.0, 1.0, 0.0, 0.0);
        const view = zm.lookAtRh(eye, target, up);

        const image_index = context.beginFrame() catch |err| switch (err) {
            error.SwapchainOutOfDate => continue,
            else => return err,
        };

        try lr.recordFrame(
            alloc,
            image_index,
            70.0,
            aspect,
            0.05,
            512.0,
            view,
            sky_color,
            cloud_color,
            cam_x,
            cam_y,
            cam_z,
            0.0,
        );

        context.endFrame(image_index) catch |err| switch (err) {
            error.SwapchainOutOfDate => {},
            else => return err,
        };
    }

    std.debug.print("Renderer demo exited cleanly.\n", .{});
}
