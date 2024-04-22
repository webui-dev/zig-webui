const std = @import("std");
const builtin = @import("builtin");

const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.zig.CrossTarget;
const Build = std.Build;
const Compile = Build.Step.Compile;
const Module = Build.Module;

const log = std.log.scoped(.WebUI);

const default_isStatic = true;
const default_enableTLS = false;

pub fn build(b: *Build) void {
    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse default_isStatic;
    const enableTLS = b.option(bool, "enable_tls", "whether lib enable tls") orelse default_enableTLS;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    log.info("link mode is {s}", .{if (isStatic) "static" else "dynamic"});

    if (enableTLS) {
        log.info("enable TLS support", .{});
        if (!target.isNative()) {
            log.info("when enable tls, not support cross compile", .{});
            std.os.exit(1);
        }
    }

    // create a options for command paramter
    const flags_options = b.addOptions();

    // add option
    flags_options.addOption(bool, "enableTLS", enableTLS);

    // create a new module for flags options
    const flags_module = flags_options.createModule();

    const webui_module = b.addModule("webui", .{
        .source_file = .{
            .path = "src/webui.zig",
        },
        .dependencies = &.{
            .{
                .name = "flags",
                .module = flags_module,
            },
        },
    });

    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .enable_tls = enableTLS,
        .is_static = isStatic,
    }).artifact("webui");

    b.installArtifact(webui);

    // build examples
    build_examples_11(b, optimize, target, webui_module, webui);
}

fn build_examples_11(b: *Build, optimize: OptimizeMode, target: CrossTarget, webui_module: *Module, webui_lib: *Compile) void {
    // we use lazyPath to get absolute path of package
    var lazy_path = Build.LazyPath{
        .path = "src/examples",
    };

    const build_all_step = b.step("build_all", "build all examples");

    const examples_path = lazy_path.getPath(b);
    var iter_dir =
        std.fs.openIterableDirAbsolute(examples_path, .{}) catch |err| {
        log.err("open examples_path failed, err is {}", .{err});
        std.os.exit(1);
    };
    defer iter_dir.close();

    var itera = iter_dir.iterate();

    while (itera.next()) |val| {
        if (val) |entry| {
            if (entry.kind == .directory) {
                const example_name = entry.name;
                const path = std.fmt.allocPrint(b.allocator, "src/examples/{s}/main.zig", .{example_name}) catch |err| {
                    log.err("fmt path for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };

                const exe = b.addExecutable(.{
                    .name = example_name,
                    .root_source_file = .{ .path = path },
                    .target = target,
                    .optimize = optimize,
                });

                exe.addModule("webui", webui_module);
                exe.linkLibrary(webui_lib);

                const exe_install = b.addInstallArtifact(exe, .{});

                build_all_step.dependOn(&exe_install.step);

                const exe_run = b.addRunArtifact(exe);
                exe_run.step.dependOn(&exe_install.step);

                const cwd = std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ examples_path, example_name }) catch |err| {
                    log.err("fmt path for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };
                exe_run.cwd = cwd;

                const step_name = std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name}) catch |err| {
                    log.err("fmt step_name for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };

                const step_desc = std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name}) catch |err| {
                    log.err("fmt step_desc for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };

                const exe_run_step = b.step(step_name, step_desc);
                exe_run_step.dependOn(&exe_run.step);
            }
        } else {
            break;
        }
    } else |err| {
        log.err("iterate examples_path failed, err is {}", .{err});
        std.os.exit(1);
    }
}
