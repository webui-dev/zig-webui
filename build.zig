const std = @import("std");
const builtin = @import("builtin");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.zig.CrossTarget;
const Compile = Build.Step.Compile;
const Module = Build.Module;

const log = std.log.scoped(.WebUI);

const min_zig_string = "0.11.0";

const default_isStatic = true;
const default_enableTLS = false;

const current_zig = builtin.zig_version;

// NOTE: we should note that when enable tls support we cannot compile with musl

comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
}

pub fn build(b: *Build) void {
    if (current_zig.minor == 11) {
        build_11(b);
    } else if (current_zig.minor == 12) {
        build_12(b);
    }
}

fn build_11(b: *Build) void {
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

    // build examples
    build_examples_11(b, optimize, target, webui_module, webui);
}

fn build_12(b: *Build) void {
    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse default_isStatic;
    const enableTLS = b.option(bool, "enable_tls", "whether lib enable tls") orelse default_enableTLS;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    log.info("link mode is {s}", .{if (isStatic) "static" else "dynamic"});

    if (enableTLS) {
        log.info("enable TLS support", .{});
        if (!target.query.isNative()) {
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

    const webui = b.dependency("webui", .{
        .target = target,
        .optimize = optimize,
        .enable_tls = enableTLS,
        .is_static = isStatic,
    }).artifact("webui");

    const webui_module = b.addModule("webui", .{
        .root_source_file = .{
            .path = "src/webui.zig",
        },
        .imports = &.{
            .{
                .name = "flags",
                .module = flags_module,
            },
        },
    });

    webui_module.linkLibrary(webui);

    // build examples
    build_examples_12(b, optimize, target, webui_module, webui);
}

fn build_examples_11(b: *Build, optimize: OptimizeMode, target: CrossTarget, webui_module: *Module, webui_lib: *Compile) void {
    // we use lazyPath to get absolute path of package
    var lazy_path = Build.LazyPath{
        .path = "src/examples",
    };

    const build_all_step = b.step("build_all", "build all examples");

    const examples_path = lazy_path.getPath(b);
    var iter_dir = if (comptime current_zig.minor == 11)
        std.fs.openIterableDirAbsolute(examples_path, .{}) catch |err| {
            log.err("open examples_path failed, err is {}", .{err});
            std.os.exit(1);
        }
    else
        std.fs.openDirAbsolute(examples_path, .{ .iterate = true }) catch |err| {
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

                if (comptime (current_zig.minor > 11)) {
                    const cwd = std.fmt.allocPrint(b.allocator, "src/examples/{s}", .{example_name}) catch |err| {
                        log.err("fmt path for examples failed, err is {}", .{err});
                        std.os.exit(1);
                    };
                    exe_run.setCwd(.{
                        .path = cwd,
                    });
                } else {
                    const cwd = std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ examples_path, example_name }) catch |err| {
                        log.err("fmt path for examples failed, err is {}", .{err});
                        std.os.exit(1);
                    };
                    exe_run.cwd = cwd;
                }

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

fn build_examples_12(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, webui_module: *Module, webui_lib: *Compile) void {
    // we use lazyPath to get absolute path of package
    var lazy_path = Build.LazyPath{
        .path = "src/examples",
    };

    const build_all_step = b.step("build_all", "build all examples");

    const examples_path = lazy_path.getPath(b);
    var iter_dir = if (comptime current_zig.minor == 11)
        std.fs.openIterableDirAbsolute(examples_path, .{}) catch |err| {
            log.err("open examples_path failed, err is {}", .{err});
            std.os.exit(1);
        }
    else
        std.fs.openDirAbsolute(examples_path, .{ .iterate = true }) catch |err| {
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

                exe.root_module.addImport("webui", webui_module);
                exe.linkLibrary(webui_lib);

                const exe_install = b.addInstallArtifact(exe, .{});

                build_all_step.dependOn(&exe_install.step);

                const exe_run = b.addRunArtifact(exe);
                exe_run.step.dependOn(&exe_install.step);

                if (comptime (current_zig.minor > 11)) {
                    const cwd = std.fmt.allocPrint(b.allocator, "src/examples/{s}", .{example_name}) catch |err| {
                        log.err("fmt path for examples failed, err is {}", .{err});
                        std.os.exit(1);
                    };
                    exe_run.setCwd(.{
                        .path = cwd,
                    });
                } else {
                    const cwd = std.fmt.allocPrint(b.allocator, "{s}/{s}", .{ examples_path, example_name }) catch |err| {
                        log.err("fmt path for examples failed, err is {}", .{err});
                        std.os.exit(1);
                    };
                    exe_run.cwd = cwd;
                }

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
