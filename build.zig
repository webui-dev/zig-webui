const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linsang = b.dependency("linsang", .{
        .target = target,
        .optimize = optimize,
    }).module("Linsang");

    const webui = b.addModule("webui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "Linsang", .module = linsang }},
    });

    const tests = b.addTest(.{ .root_module = webui });
    const test_step = b.step("test", "Run unit and integration tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const bridge_tests = b.addSystemCommand(&.{ "node", "--test" });
    bridge_tests.addFileArg(b.path("src/bridge.test.js"));
    test_step.dependOn(&bridge_tests.step);

    const minimal = b.addExecutable(.{
        .name = "minimal",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/minimal/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "webui", .module = webui }},
        }),
    });
    b.installArtifact(minimal);

    const run = b.addRunArtifact(minimal);
    run.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the minimal example");
    run_step.dependOn(&run.step);
}
