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

    var deps: [2]*Compile = .{
        build_c_webui(b, optimize, target, isStatic, enableTLS),
        build_c_civetweb(b, optimize, target, isStatic, enableTLS),
    };

    const webui = build_webui(b, optimize, target, isStatic, &deps);

    // create a options for command paramter
    const flags_options = b.addOptions();

    // add option
    flags_options.addOption(bool, "enableTLS", enableTLS);

    // add optios to webui
    webui.addOptions("flags", flags_options);

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

    // build examples
    build_examples(b, optimize, target, webui_module, webui);

    // this will build normal C demo text_editor
    build_text_editor(b, optimize, target, &deps);
}

fn build_examples(b: *Build, optimize: OptimizeMode, target: CrossTarget, webui_module: *Module, webui_lib: *Compile) void {
    var dir = if (comptime (current_zig.minor > 11))
        std.fs.cwd().openDir("./src/examples", .{ .iterate = true }) catch @panic("try create iterate of examples failed!")
    else
        std.fs.cwd().openIterableDir("./src/examples", .{}) catch @panic("try create iterate of examples failed!");
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next()) |entry| {
        if (entry) |val| {
            if (val.kind == .directory) {
                // we only itreate directory

                const path = std.fmt.allocPrint(b.allocator, "src/examples/{s}/main.zig", .{val.name}) catch |err| {
                    log.err("fmt path for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };

                const cwd = std.fmt.allocPrint(b.allocator, "src/examples/{s}", .{val.name}) catch |err| {
                    log.err("fmt path for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };

                const exe = b.addExecutable(.{
                    .name = val.name,
                    .root_source_file = .{ .path = path },
                    .target = target,
                    .optimize = optimize,
                });

                exe.addModule("webui", webui_module);
                exe.linkLibrary(webui_lib);

                const exe_install = b.addInstallArtifact(exe, .{});

                const exe_run = b.addRunArtifact(exe);
                exe_run.step.dependOn(&exe_install.step);

                if (comptime (current_zig.minor > 11)) {
                    exe_run.setCwd(.{
                        .path = cwd,
                    });
                } else {
                    exe_run.cwd = cwd;
                }

                const step_name = std.fmt.allocPrint(b.allocator, "run_{s}", .{val.name}) catch |err| {
                    log.err("fmt step_name for examples failed, err is {}", .{err});
                    std.os.exit(1);
                };

                const step_desc = std.fmt.allocPrint(b.allocator, "run_{s}", .{val.name}) catch |err| {
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
        log.err("iterate examples failed, err is {}", .{err});
        std.os.exit(1);
    }
}

fn build_webui(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool, dependencies: []*Compile) *Compile {
    const webui = if (is_static) b.addStaticLibrary(.{
        .name = "webui",
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = "webui",
        .target = target,
        .optimize = optimize,
    });

    for (dependencies) |value| {
        webui.linkLibrary(value);
    }

    webui.installHeader("webui/include/webui.h", "webui.h");

    b.installArtifact(webui);

    return webui;
}

/// build C demo text_editor
fn build_text_editor(b: *Build, optimize: OptimizeMode, target: CrossTarget, dependencies: []*Compile) void {
    const text_editor = b.addExecutable(.{
        .name = "text_editor",
        .optimize = optimize,
        .target = target,
    });

    text_editor.addCSourceFile(.{
        .file = .{
            .path = "webui/examples/C/text-editor/main.c",
        },
        .flags = &[_][]const u8{},
    });

    text_editor.linkLibC();

    text_editor.addIncludePath(.{
        .path = "webui/include",
    });
    for (dependencies) |value| {
        text_editor.linkLibrary(value);
    }

    text_editor.linkSystemLibrary("pthread");
    text_editor.linkSystemLibrary("m");

    const install_text_editor = b.addInstallArtifact(text_editor, .{});

    const text_editor_step = b.step("text_editor", "build text_editor");

    text_editor_step.dependOn(&install_text_editor.step);

    const run_text_editor_cmd = b.addRunArtifact(text_editor);

    // This is a compatibility issue
    // we use comptime to read the version number and decide which API to use
    if (comptime (current_zig.minor > 11)) {
        run_text_editor_cmd.setCwd(.{
            .path = "webui/examples/C/text-editor",
        });
    } else {
        run_text_editor_cmd.cwd = "webui/examples/C/text-editor";
    }

    run_text_editor_cmd.step.dependOn(&install_text_editor.step);

    const run_text_editor_step = b.step("run_text_editor", "Run the text_editor");
    run_text_editor_step.dependOn(&run_text_editor_cmd.step);
}

fn build_c_webui(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool, enable_tls: bool) *Compile {
    const name = "webui_c";
    const webui_c = if (is_static) b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });

    webui_c.addCSourceFile(.{
        .file = .{
            .path = "webui/src/webui.c",
        },
        .flags = if (enable_tls)
            &[_][]const u8{
                "-DNO_SSL",
                "-DWEBUI_TLS",
                "-DNO_SSL_DL",
                "-DOPENSSL_API_1_1",
            }
        else
            &[_][]const u8{
                "-DNO_SSL",
            },
    });

    webui_c.linkLibC();

    webui_c.addIncludePath(.{
        .path = "webui/include",
    });

    return webui_c;
}

fn build_c_civetweb(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool, enable_tls: bool) *Compile {
    const name = "civetweb_c";
    const civetweb_c = if (is_static) b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });

    civetweb_c.addIncludePath(.{
        .path = "webui/include",
    });

    const cflags = if (target.os_tag == .windows and !enable_tls) &[_][]const u8{
        "-DNO_SSL",
        "-DNDEBUG",
        "-DNO_CACHING",
        "-DNO_CGI",
        "-DUSE_WEBSOCKET",
        "-DMUST_IMPLEMENT_CLOCK_GETTIME",
    } else if (target.os_tag == .windows and enable_tls) &[_][]const u8{
        "-DNDEBUG",
        "-DNO_CACHING",
        "-DNO_CGI",
        "-DUSE_WEBSOCKET",
        "-DWEBUI_TLS",
        "-DNO_SSL_DL",
        "-DOPENSSL_API_1_1",
        "-DMUST_IMPLEMENT_CLOCK_GETTIME",
    } else if (target.os_tag != .windows and enable_tls)
        &[_][]const u8{
            "-DNDEBUG",
            "-DNO_CACHING",
            "-DNO_CGI",
            "-DUSE_WEBSOCKET",
            "-DWEBUI_TLS",
            "-DNO_SSL_DL",
            "-DOPENSSL_API_1_1",
        }
    else
        &[_][]const u8{
            "-DNO_SSL",
            "-DNDEBUG",
            "-DNO_CACHING",
            "-DNO_CGI",
            "-DUSE_WEBSOCKET",
        };

    civetweb_c.addCSourceFile(.{
        .file = .{
            .path = "webui/src/civetweb/civetweb.c",
        },
        .flags = cflags,
    });

    civetweb_c.linkLibC();

    if (target.os_tag == .windows) {
        civetweb_c.linkSystemLibrary("ws2_32");
        if (enable_tls) {
            civetweb_c.linkSystemLibrary("bcrypt");
        }
    }
    if (enable_tls) {
        civetweb_c.linkSystemLibrary("ssl");
        civetweb_c.linkSystemLibrary("crypto");
    }

    return civetweb_c;
}
