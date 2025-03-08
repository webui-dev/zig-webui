const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;

const min_zig_string = "0.12.0";
const current_zig = builtin.zig_version;

// NOTE: we should note that when enable tls support we cannot compile with musl

comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
}

const log = std.log.scoped(.WebUI);
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.zig.CrossTarget;
const Compile = Build.Step.Compile;
const Module = Build.Module;

const default_isStatic = true;
const default_enableTLS = false;

pub fn build(b: *Build) !void {
    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse default_isStatic;
    const enableTLS = b.option(bool, "enable_tls", "whether lib enable tls") orelse default_enableTLS;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (enableTLS) {
        log.info("enable TLS support", .{});
        if (!target.query.isNative()) {
            log.info("when enable tls, not support cross compile", .{});
            std.posix.exit(1);
        }
    }

    // create a options for command parameter
    const flags_options = b.addOptions();

    // add option
    flags_options.addOption(bool, "enableTLS", enableTLS);

    // create a new module for flags options
    const flags_module = flags_options.createModule();

    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .dynamic = !isStatic,
        .@"enable-tls" = enableTLS,
        .verbose = .err,
    });

    const webui_module = b.addModule("webui", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "webui.zig" })),
        .imports = &.{
            .{
                .name = "flags",
                .module = flags_module,
            },
        },
    });
    webui_module.linkLibrary(webui.artifact("webui"));
    if (!isStatic) {
        b.installArtifact(webui.artifact("webui"));
    }

    // generate docs
    generate_docs(b, optimize, target, flags_module);

    // build examples
    build_examples(b, optimize, target, webui_module, webui.artifact("webui")) catch |err| {
        log.err("failed to build examples: {}", .{err});
        std.process.exit(1);
    };
}

fn generate_docs(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, flags_module: *Module) void {
    const webui_lib = b.addObject(.{
        .name = "webui_lib",
        .root_source_file = b.path(b.pathJoin(&.{ "src", "webui.zig" })),
        .target = target,
        .optimize = optimize,
    });

    webui_lib.root_module.addImport("flags", flags_module);

    const docs_step = b.step("docs", "Generate docs");

    const docs_install = b.addInstallDirectory(.{
        .source_dir = webui_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}

fn build_examples(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, webui_module: *Module, webui_lib: *Compile) !void {

    // we use lazyPath to get absolute path of package
    var lazy_path = b.path("examples");

    const build_all_step = b.step("examples", "build all examples");

    const examples_path = lazy_path.getPath(b);

    var iter_dir = std.fs.openDirAbsolute(examples_path, .{ .iterate = true })
        catch |err| {
            switch (err) {
                error.FileNotFound => return,
                else => return err,
            }
        };
    defer iter_dir.close();

    var itera = iter_dir.iterate();

    while (try itera.next()) |val| {
        if (val.kind != .directory) {
            continue;
        }

        const example_name = val.name;
        const path = b.pathJoin(&.{ "examples", example_name, "main.zig" });

        const exe = b.addExecutable(.{
            .name = example_name,
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("webui", webui_module);
        exe.linkLibrary(webui_lib);

        const exe_install = b.addInstallArtifact(exe, .{});

        build_all_step.dependOn(&exe_install.step);

        const exe_run = b.addRunArtifact(exe);
        exe_run.step.dependOn(&exe_install.step);

        const cwd = b.path(b.pathJoin(&.{ "examples", example_name }));

        exe_run.setCwd(cwd);

        const step_name = try std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name});

        const step_desc = try std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name});

        const exe_run_step = b.step(step_name, step_desc);
        exe_run_step.dependOn(&exe_run.step);
    }
}
