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

pub fn build(b: *Build) !void {
    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse default_isStatic;
    const enableTLS = b.option(bool, "enable_tls", "whether lib enable tls") orelse default_enableTLS;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    log.info("link mode is {s}", .{if (isStatic) "static" else "dynamic"});

    if (enableTLS) {
        log.info("enable TLS support", .{});
        if (!target.query.isNative()) {
            log.info("when enable tls, not support cross compile", .{});
            std.posix.exit(1);
        }
    }

    // create a options for command paramter
    const flags_options = b.addOptions();

    // add option
    flags_options.addOption(bool, "enableTLS", enableTLS);

    // create a new module for flags options
    const flags_module = flags_options.createModule();

    const webui = try webui_c(b, optimize, target, isStatic, enableTLS);

    const webui_module = b.addModule("webui", .{
        .root_source_file = b.path("src/webui.zig"),
        .imports = &.{
            .{
                .name = "flags",
                .module = flags_module,
            },
        },
    });

    webui_module.linkLibrary(webui);

    // install webui c lib
    install_webui_c(b, webui);

    // generate docs
    generate_docs(b, optimize, target, flags_module);

    // build examples
    build_examples_12(b, optimize, target, webui_module, webui);
}

/// this function to build webui from c code
fn webui_c(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, is_static: bool, enable_tls: bool) !*Compile {
    const webui_dep = b.dependency("webui", .{});

    const name = "webui";
    const webui = if (is_static) b.addStaticLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = name,
        .target = target,
        .optimize = optimize,
    });

    // basical flags for civetweb
    const basic_flags = [_][]const u8{ "-DNDEBUG", "-DNO_CACHING", "-DNO_CGI", "-DUSE_WEBSOCKET" };

    // when enable tls
    const tls_flags = [_][]const u8{ "-DWEBUI_TLS", "-DNO_SSL_DL", "-DOPENSSL_API_1_1" };
    // when disable tls
    const no_tls_flags = [_][]const u8{"-DNO_SSL"};

    var civetweb_flags = std.ArrayList([]const u8).init(b.allocator);
    defer civetweb_flags.deinit();

    try civetweb_flags.appendSlice(&basic_flags);
    try civetweb_flags.appendSlice(if (enable_tls) &tls_flags else &no_tls_flags);
    if (target.result.os.tag == .windows) {
        try civetweb_flags.append("-DMUST_IMPLEMENT_CLOCK_GETTIME");
    }

    webui.addCSourceFile(.{
        .file = webui_dep.path("src/webui.c"),
        .flags = if (enable_tls) &tls_flags else &no_tls_flags,
    });

    webui.addCSourceFile(.{
        .file = webui_dep.path("src/civetweb/civetweb.c"),
        .flags = civetweb_flags.items,
    });

    webui.linkLibC();

    webui.addIncludePath(webui_dep.path("include"));
    webui.installHeader(webui_dep.path(b.pathJoin(&[_][]const u8{ "include", "webui.h" })), "webui.h");

    // for windows build
    if (target.result.os.tag == .windows) {
        webui.linkSystemLibrary("ws2_32");
        webui.linkSystemLibrary("Ole32");
        if (target.result.abi == .msvc) {
            webui.linkSystemLibrary("Advapi32");
            webui.linkSystemLibrary("Shell32");
            webui.linkSystemLibrary("user32");
        }
        if (enable_tls) {
            webui.linkSystemLibrary("bcrypt");
        }
    } else if (target.result.os.tag == .macos) {
        webui.addCSourceFile(.{
            .file = webui_dep.path("src/webview/wkwebview.m"),
            .flags = &.{},
        });
        webui.linkFramework("Cocoa");
        webui.linkFramework("WebKit");
    }

    if (enable_tls) {
        webui.linkSystemLibrary("ssl");
        webui.linkSystemLibrary("crypto");
    }

    return webui;
}

fn install_webui_c(b: *Build, lib: *Compile) void {
    const step = b.step("lib", "Install lib");
    step.dependOn(&b.addInstallArtifact(lib, .{}).step);
}

fn generate_docs(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, flags_module: *Module) void {
    const webui_lib = b.addObject(.{
        .name = "webui_lib",
        .root_source_file = b.path("src/webui.zig"),
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

fn build_examples_12(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget, webui_module: *Module, webui_lib: *Compile) void {
    // we use lazyPath to get absolute path of package
    var lazy_path = b.path("examples");

    const build_all_step = b.step("build_all", "build all examples");

    const examples_path = lazy_path.getPath(b);

    var iter_dir =
        std.fs.openDirAbsolute(examples_path, .{ .iterate = true }) catch |err| {
        log.info("open examples_path failed, err is {}", .{err});
        return;
    };
    defer iter_dir.close();

    var itera = iter_dir.iterate();

    while (itera.next()) |val| {
        if (val) |entry| {
            if (entry.kind == .directory) {
                const example_name = entry.name;
                const path = b.pathJoin(&[_][]const u8{ "examples", example_name, "main.zig" });

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

                const cwd = b.path(b.pathJoin(&[_][]const u8{ "examples", example_name }));

                exe_run.setCwd(cwd);

                const step_name = std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name}) catch |err| {
                    log.err("fmt step_name for examples failed, err is {}", .{err});
                    std.posix.exit(1);
                };

                const step_desc = std.fmt.allocPrint(b.allocator, "run_{s}", .{example_name}) catch |err| {
                    log.err("fmt step_desc for examples failed, err is {}", .{err});
                    std.posix.exit(1);
                };

                const exe_run_step = b.step(step_name, step_desc);
                exe_run_step.dependOn(&exe_run.step);
            }
        } else {
            break;
        }
    } else |err| {
        log.err("iterate examples_path failed, err is {}", .{err});
        std.posix.exit(1);
    }
}
