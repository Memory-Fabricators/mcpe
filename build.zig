const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(bool, "use-llvm", "Use LLVM for compilation") orelse true;
    const use_lld = b.option(bool, "use-lld", "Use LLD for linking") orelse false;

    const vk_sdk_abs = b.graph.environ_map.get("VULKAN_SDK") orelse "/usr/local";

    const random_mod = b.addModule("random", .{
        .root_source_file = b.path("src/util/random.zig"),
        .target = target,
    });

    const math_mod = b.addModule("math", .{
        .root_source_file = b.path("src/util/math.zig"),
        .target = target,
    });

    const world_mod = b.addModule("world", .{
        .root_source_file = b.path("src/world/levelgen/random_level_source.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "random", .module = random_mod },
        },
    });

    const png_mod = b.addModule("png", .{
        .root_source_file = b.path("src/util/png.zig"),
        .target = target,
    });

    const renderer_mod = b.addModule("renderer", .{
        .root_source_file = b.path("src/client/renderer/renderer.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "random", .module = random_mod },
            .{ .name = "world", .module = world_mod },
            .{ .name = "png", .module = png_mod },
        },
    });

    // Compile shaders (glslc must be on PATH or in VulkanSDK)
    const shader_step = b.step("shaders", "Compile GLSL shaders to SPIR-V");
    const shader_dir = "src/client/renderer/shaders";
    const glslc = b.pathJoin(&.{ vk_sdk_abs, "bin/glslc" });
    for ([_][]const u8{
        shader_dir ++ "/terrain.vert",
        shader_dir ++ "/terrain.frag",
        shader_dir ++ "/sky.vert",
        shader_dir ++ "/sky.frag",
        shader_dir ++ "/clouds.vert",
        shader_dir ++ "/clouds.frag",
    }) |src| {
        const out = b.fmt("{s}.spv", .{src});
        const run = b.addSystemCommand(&.{ glslc, src, "-o", out });
        shader_step.dependOn(&run.step);
    }
    const renderer_demo_mod = b.createModule(.{
        .root_source_file = b.path("src/client/renderer/demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "renderer",
                .module = renderer_mod,
            },
            .{
                .name = "math",
                .module = math_mod,
            },
        },
    });
    // SDL3 dylib
    renderer_demo_mod.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    renderer_demo_mod.addRPath(.{ .cwd_relative = "/usr/local/lib" });
    renderer_demo_mod.linkSystemLibrary("SDL3", .{});
    // Vulkan loader dylib (MoltenVK-backed, from VulkanSDK)
    renderer_demo_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ vk_sdk_abs, "lib" }) });
    renderer_demo_mod.addRPath(.{ .cwd_relative = b.pathJoin(&.{ vk_sdk_abs, "lib" }) });
    renderer_demo_mod.linkSystemLibrary("vulkan", .{});
    renderer_demo_mod.link_libc = true;

    const renderer_exe = b.addExecutable(.{
        .name = "renderer-demo",
        .root_module = renderer_demo_mod,
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    b.installArtifact(renderer_exe);

    const run_renderer_step = b.step("run-renderer", "Run the Vulkan renderer demo");
    const run_rnd = b.addRunArtifact(renderer_exe);
    // Use kosmickrisp instead of moltenvk since it is more conformant
    const vk_icd = b.pathJoin(&.{ vk_sdk_abs, "share/vulkan/icd.d/libkosmickrisp_icd.json" });
    const vk_layers = b.pathJoin(&.{ vk_sdk_abs, "share/vulkan/explicit_layer.d" });
    const vk_dyld = b.pathJoin(&.{ vk_sdk_abs, "lib" });
    run_rnd.setEnvironmentVariable("VK_ICD_FILENAMES", vk_icd);
    run_rnd.setEnvironmentVariable("VK_DRIVER_FILES", vk_icd);
    run_rnd.setEnvironmentVariable("VK_ADD_LAYER_PATH", vk_layers);
    run_rnd.setEnvironmentVariable("VK_LAYER_PATH", vk_layers);
    run_rnd.setEnvironmentVariable("DYLD_LIBRARY_PATH", vk_dyld);
    // MoltenVK: async queue submit so vkQueueSubmit returns immediately
    // (correct Vulkan semantics; synchronous is MoltenVK-specific non-standard default)
    run_rnd.setEnvironmentVariable("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "0");
    // Prevent Metal shader compilation from making the GPU appear hung (TDR).
    // With DISABLE_OPTIMIZATION, compilation should take <1s anyway.
    run_rnd.setEnvironmentVariable("MVK_CONFIG_METAL_COMPILE_TIMEOUT", "5000");
    run_renderer_step.dependOn(&run_rnd.step);
    run_rnd.step.dependOn(b.getInstallStep());

    // ---- Core modules ----
    const zig_raknet = b.addModule("zig-raknet", .{
        .root_source_file = b.path("src/raknet/raknet.zig"),
        .target = target,
    });

    _ = b.addModule("network", .{
        .root_source_file = b.path("src/network/packet.zig"),
        .target = target,
        .imports = &.{.{ .name = "raknet", .module = zig_raknet }},
    });

    _ = b.addModule("nbt", .{
        .root_source_file = b.path("src/nbt/tag.zig"),
        .target = target,
    });

    _ = b.addModule("locale", .{
        .root_source_file = b.path("src/locale/i18n.zig"),
        .target = target,
    });

    _ = b.addModule("levelgen", .{
        .root_source_file = b.path("src/world/levelgen/random_level_source.zig"),
        .target = target,
        .imports = &.{
            .{
                .name = "random",
                .module = random_mod,
            },
            .{
                .name = "math",
                .module = math_mod,
            },
        },
    });

    // ---- Example: ping server ----
    const ping_server_exe = b.addExecutable(.{
        .name = "ping-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/raknet/examples/ping_server.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zig-raknet", .module = zig_raknet }},
        }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    b.installArtifact(ping_server_exe);

    const run_server_step = b.step("run-server", "Run the ping server example");
    const run_srv = b.addRunArtifact(ping_server_exe);
    run_server_step.dependOn(&run_srv.step);
    run_srv.step.dependOn(b.getInstallStep());
    run_srv.addPassthruArgs();

    // ---- Tests ----
    const test_step = b.step("test", "Run all tests");

    const raknet_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/raknet/raknet.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    const run_raknet_tests = b.addRunArtifact(raknet_tests);
    test_step.dependOn(&run_raknet_tests.step);
    run_raknet_tests.step.dependOn(b.getInstallStep());

    const network_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/network/packet.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "raknet", .module = zig_raknet }},
        }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    const run_net_tests = b.addRunArtifact(network_tests);
    test_step.dependOn(&run_net_tests.step);
    run_net_tests.step.dependOn(b.getInstallStep());

    const nbt_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/nbt/tag.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    const run_nbt_tests = b.addRunArtifact(nbt_tests);
    test_step.dependOn(&run_nbt_tests.step);
    run_nbt_tests.step.dependOn(b.getInstallStep());

    const locale_tests = b.addTest(.{
        .root_module = b.createModule(.{ .root_source_file = b.path("src/locale/i18n.zig"), .target = target, .optimize = optimize }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    const run_locale_tests = b.addRunArtifact(locale_tests);
    test_step.dependOn(&run_locale_tests.step);
    run_locale_tests.step.dependOn(b.getInstallStep());

    const levelgen_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/world/levelgen/random_level_source.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "random", .module = random_mod }},
        }),
        .use_llvm = use_llvm,
        .use_lld = use_lld,
    });
    const run_levelgen_tests = b.addRunArtifact(levelgen_tests);
    test_step.dependOn(&run_levelgen_tests.step);
    run_levelgen_tests.step.dependOn(b.getInstallStep());
}
