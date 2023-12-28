const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.zig.CrossTarget;
const Compile = Build.Step.Compile;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const civetweb_static = build_civetweb(b, optimize, target, true);
    const webui_static = build_webui(b, optimize, target, true);

    const lib_step = b.step("library", "build c library");

    lib_step.dependOn(&civetweb_static.step);
    lib_step.dependOn(&webui_static.step);

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

    text_editor.linkLibrary(webui_static);
    text_editor.linkLibrary(civetweb_static);
    text_editor.linkSystemLibrary("pthread");
    text_editor.linkSystemLibrary("m");

    b.installArtifact(text_editor);

    const text_editor_step = b.step("text_editor", "build text_editor");

    text_editor_step.dependOn(&text_editor.step);
}

fn build_webui(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool) *Compile {
    const webui = if (is_static) b.addStaticLibrary(.{
        .name = "webui",
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = "webui",
        .target = target,
        .optimize = optimize,
    });

    webui.addCSourceFile(.{
        .file = .{
            .path = "webui/src/webui.c",
        },
        .flags = &[_][]const u8{
            "-DNO_SSL",
        },
    });

    webui.linkLibC();

    webui.addIncludePath(.{
        .path = "webui/include",
    });

    b.installArtifact(webui);

    return webui;
}

fn build_civetweb(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool) *Compile {
    const civetweb = if (is_static) b.addStaticLibrary(.{
        .name = "civetweb",
        .target = target,
        .optimize = optimize,
    }) else b.addSharedLibrary(.{
        .name = "civetweb",
        .target = target,
        .optimize = optimize,
    });

    civetweb.addCSourceFile(.{
        .file = .{
            .path = "webui/src/civetweb/civetweb.c",
        },
        .flags = if (target.os_tag == .windows) &[_][]const u8{
            "-DNO_SSL",
            "-DNDEBUG",
            "-DNO_CACHING",
            "-DNO_CGI",
            "-DUSE_WEBSOCKET",
            "-DMUST_IMPLEMENT_CLOCK_GETTIME",
        } else &[_][]const u8{
            "-DNO_SSL",
            "-DNDEBUG",
            "-DNO_CACHING",
            "-DNO_CGI",
            "-DUSE_WEBSOCKET",
        },
    });

    civetweb.linkLibC();

    if (target.os_tag == .windows) {
        civetweb.linkSystemLibrary("ws2_32");
    }

    civetweb.addIncludePath(.{
        .path = "webui/include",
    });

    b.installArtifact(civetweb);

    return civetweb;
}
