const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(bool, "use-llvm", "Use LLVM for compilation") orelse true;
    const use_lld = b.option(bool, "use-lld", "Use LLD for linking") orelse false;

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

    const random_mod = b.addModule("random", .{
        .root_source_file = b.path("src/util/random.zig"),
        .target = target,
    });

    _ = b.addModule("levelgen", .{
        .root_source_file = b.path("src/world/levelgen/random_level_source.zig"),
        .target = target,
        .imports = &.{.{ .name = "random", .module = random_mod }},
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
