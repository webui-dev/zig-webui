const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;

// Minimum required Zig version for this project
const min_zig_string = "0.12.0";
const current_zig = builtin.zig_version;

// NOTE: we should note that when enable tls support we cannot compile with musl

// Compile-time check to ensure the Zig version meets the minimum requirement
comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
}

// Define logger and useful type aliases
const log = std.log.scoped(.WebUI);
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.Target.Query;
const Compile = Build.Step.Compile;
const Module = Build.Module;

// Default build configuration options
const default_isStatic = true;
const default_enableTLS = false;

pub fn build(b: *Build) !void {
    // Parse command-line options or use defaults
    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse default_isStatic;
    const enableTLS = b.option(bool, "enable_tls", "whether lib enable tls") orelse default_enableTLS;
    const enableWebUILog = b.option(bool, "enable_webui_log", "whether lib enable tls") orelse default_enableTLS;

    // Standard build options for target and optimization
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // TLS support has some limitations
    if (enableTLS) {
        log.info("enable TLS support", .{});
        if (!target.query.isNative()) {
            log.info("when enable tls, not support cross compile", .{});
            std.posix.exit(1);
        }
    }

    // Create build options that will be used as a module
    const flags_options = b.addOptions();

    // Configure compile-time options
    flags_options.addOption(bool, "enableTLS", enableTLS);

    // Create a module that exposes the options
    const flags_module = flags_options.createModule();

    // Get the webui dependency with appropriate options
    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .dynamic = !isStatic,
        .@"enable-tls" = enableTLS,
        .@"enable-webui-log" = enableWebUILog,
        .verbose = .err,
    });

    // Create the webui module that applications can import
    const webui_module = b.addModule("webui", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "webui.zig" })),
        .imports = &.{
            .{
                .name = "flags",
                .module = flags_module,
            },
        },
    });
    // Link against the webui library
    webui_module.linkLibrary(webui.artifact("webui"));
    if (!isStatic) {
        // For dynamic libraries, install the shared library
        b.installArtifact(webui.artifact("webui"));
    }

    // Setup documentation generation
    generate_docs(b, optimize, target, flags_module);

    // Build example applications
    build_examples(b, optimize, target, webui_module, webui.artifact("webui")) catch |err| {
        log.err("failed to build examples: {}", .{err});
        std.process.exit(1);
    };
}

// Function to generate API documentation
fn generate_docs(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, flags_module: *Module) void {
    // Create a temporary object for documentation generation
    const webui_lib = b.addObject(if (builtin.zig_version.minor == 14) .{
        .name = "webui_lib",
        .root_source_file = b.path(b.pathJoin(&.{ "src", "webui.zig" })),
        .target = target,
        .optimize = optimize,
    } else .{
        .name = "webui_lib",
        .root_module = b.addModule("webui_lib", .{
            .root_source_file = b.path(b.pathJoin(&.{ "src", "webui.zig" })),
            .target = target,
            .optimize = optimize,
        }),
    });

    webui_lib.root_module.addImport("flags", flags_module);

    // Create a build step for documentation
    const docs_step = b.step("docs", "Generate docs");

    // Setup documentation installation
    const docs_install = b.addInstallDirectory(.{
        .source_dir = webui_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}

// Function to build all example applications
fn build_examples(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, webui_module: *Module, webui_lib: *Compile) !void {

    // Get the absolute path to the examples directory
    var lazy_path = b.path("examples");

    // Create a step to build all examples
    const build_all_step = b.step("examples", "build all examples");

    const examples_path = lazy_path.getPath(b);

    // Open the examples directory for iteration
    var iter_dir = std.fs.openDirAbsolute(
        examples_path,
        .{ .iterate = true },
    ) catch |err| {
        switch (err) {
            error.FileNotFound => return,
            else => return err,
        }
    };
    defer iter_dir.close();

    var itera = iter_dir.iterate();

    // Iterate through all subdirectories in the examples directory
    while (try itera.next()) |val| {
        if (val.kind != .directory) {
            continue;
        }

        const example_name = val.name;
        const path = b.pathJoin(&.{ "examples", example_name, "main.zig" });

        // Create an executable for each example
        const exe = b.addExecutable(if (builtin.zig_version.minor == 14) .{
            .name = example_name,
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        } else .{
            .name = example_name,
            .root_module = b.addModule(example_name, .{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });

        // Add the webui module and link against the library
        exe.root_module.addImport("webui", webui_module);
        exe.linkLibrary(webui_lib);

        // Setup installation
        const exe_install = b.addInstallArtifact(exe, .{});

        build_all_step.dependOn(&exe_install.step);

        // Create a run step for the example
        const exe_run = b.addRunArtifact(exe);
        exe_run.step.dependOn(&exe_install.step);

        // Set the working directory for the run
        const cwd = b.path(b.pathJoin(&.{ "examples", example_name }));
        exe_run.setCwd(cwd);

        // Create a named step to run this specific example
        const step_name = try std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name});
        const step_desc = try std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name});

        const exe_run_step = b.step(step_name, step_desc);
        exe_run_step.dependOn(&exe_run.step);
    }
}
