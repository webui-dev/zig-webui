const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.Target.Query;
const Compile = Build.Step.Compile;
const Module = Build.Module;
const builtin = @import("builtin");
const current_zig = builtin.zig_version;

const min_zig_string = "0.14.0";
// NOTE: when enable tls support we cannot compile with musl
comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        const err_msg = std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig });
        @compileError(err_msg);
    }
}

const log = std.log.scoped(.WebUI);
const default_isStatic = true;
const default_enableTLS = false;
const default_enableWebUILog = false;

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse default_isStatic;
    const enableTLS = b.option(bool, "enable_tls", "whether lib enable tls") orelse default_enableTLS;
    const enableWebUILog = b.option(bool, "enable_webui_log", "whether lib enable webui log") orelse default_enableWebUILog;

    if (enableTLS) log.info("enable TLS support", .{});

    // TLS does not support cross compilation
    if (enableTLS and !target.query.isNative()) {
        log.err("TLS support is only available for native builds", .{});
        std.process.exit(1);
    }

    const flags_options = b.addOptions();
    flags_options.addOption(bool, "enableTLS", enableTLS);

    const flags_module = flags_options.createModule();

    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .dynamic = !isStatic,
        .@"enable-tls" = enableTLS,
        .@"enable-webui-log" = enableWebUILog,
        .verbose = .err,
    });
    const webui_module = b.addModule("webui", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "webui.zig" })),
        .imports = &.{.{
            .name = "flags",
            .module = flags_module,
        }},
    });
    webui_module.linkLibrary(webui.artifact("webui"));

    if (!isStatic) b.installArtifact(webui.artifact("webui"));

    const compat_module = b.addModule("compat", .{ .root_source_file = b.path(b.pathJoin(&.{ "examples", "compat.zig" })) });

    buildExamples(b, .{
        .optimize = optimize,
        .target = target,
        .webui_module = webui_module,
        .compat_module = compat_module,
    }) catch |err| {
        log.err("failed to build examples: {}", .{err});
        std.process.exit(1);
    };

    generateDocs(b, .{
        .optimize = optimize,
        .target = target,
        .flags_module = flags_module,
    });
}

// ========== Options Structures ==========

const BuildExamplesOptions = struct {
    optimize: OptimizeMode,
    target: Build.ResolvedTarget,
    webui_module: *Module,
    compat_module: *Module,
};

const GenerateDocsOptions = struct {
    optimize: OptimizeMode,
    target: Build.ResolvedTarget,
    flags_module: *Module,
};

// ========== Helper Functions ==========

/// Create an object artifact with version compatibility
fn createObject(
    b: *Build,
    name: []const u8,
    root_source: Build.LazyPath,
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
) *Compile {
    if (builtin.zig_version.minor == 14) {
        return b.addObject(.{
            .name = name,
            .root_source_file = root_source,
            .target = target,
            .optimize = optimize,
        });
    } else {
        return b.addObject(.{
            .name = name,
            .root_module = b.addModule(name, .{
                .root_source_file = root_source,
                .target = target,
                .optimize = optimize,
            }),
        });
    }
}

/// Create an executable artifact with version compatibility
fn createExecutable(
    b: *Build,
    name: []const u8,
    root_source: Build.LazyPath,
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
) *Compile {
    if (builtin.zig_version.minor == 14) {
        return b.addExecutable(.{
            .name = name,
            .root_source_file = root_source,
            .target = target,
            .optimize = optimize,
        });
    } else {
        return b.addExecutable(.{
            .name = name,
            .root_module = b.addModule(name, .{
                .root_source_file = root_source,
                .target = target,
                .optimize = optimize,
            }),
        });
    }
}

// ========== Documentation Generation ==========

fn generateDocs(b: *Build, options: GenerateDocsOptions) void {
    const webui_lib = createObject(
        b,
        "webui_lib",
        b.path(b.pathJoin(&.{ "src", "webui.zig" })),
        options.target,
        options.optimize,
    );

    webui_lib.root_module.addImport("flags", options.flags_module);

    const docs_step = b.step("docs", "Generate docs");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = webui_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}

// ========== Examples Building ==========

fn buildExamples(b: *Build, options: BuildExamplesOptions) !void {
    const lazy_path = b.path("examples");
    const build_all_step = b.step("examples", "build all examples");
    const examples_path = lazy_path.getPath(b);

    var examples_dir = std.fs.openDirAbsolute(examples_path, .{ .iterate = true }) catch |err| {
        switch (err) {
            error.FileNotFound => return,
            else => return err,
        }
    };
    defer examples_dir.close();

    var iter = examples_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) {
            continue;
        }

        try buildExample(b, entry.name, options, build_all_step);
    }
}

fn buildExample(
    b: *Build,
    example_name: []const u8,
    options: BuildExamplesOptions,
    build_all_step: *Build.Step,
) !void {
    const main_path = b.pathJoin(&.{ "examples", example_name, "main.zig" });
    const exe = createExecutable(
        b,
        example_name,
        b.path(main_path),
        options.target,
        options.optimize,
    );

    exe.root_module.addImport("webui", options.webui_module);
    exe.root_module.addImport("compat", options.compat_module);

    // Install step
    const exe_install = b.addInstallArtifact(exe, .{});
    build_all_step.dependOn(&exe_install.step);

    // Run step
    const exe_run = b.addRunArtifact(exe);
    exe_run.step.dependOn(&exe_install.step);
    exe_run.setCwd(b.path(b.pathJoin(&.{ "examples", example_name })));

    const step_name = try std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name});
    const step_desc = try std.fmt.allocPrint(b.allocator, "run {s} example", .{example_name});

    const exe_run_step = b.step(step_name, step_desc);
    exe_run_step.dependOn(&exe_run.step);
}

