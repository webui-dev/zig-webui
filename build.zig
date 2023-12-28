const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.zig.CrossTarget;
const Compile = Build.Step.Compile;

pub fn build(b: *Build) void {
    const isStatic = b.option(bool, "is_static", "whether lib is static") orelse true;
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const civetweb_c = build_c_civetweb(b, optimize, target, isStatic);
    const webui_c = build_c_webui(b, optimize, target, isStatic);

    const install_civetweb_c = b.addInstallArtifact(civetweb_c, .{});
    const install_webui_c = b.addInstallArtifact(webui_c, .{});

    const lib_step = b.step("c_lib", "build c library");

    lib_step.dependOn(&install_civetweb_c.step);
    lib_step.dependOn(&install_webui_c.step);

    const webui = b.addStaticLibrary(.{
        .name = "webui",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/webui.zig" },
        .target = target,
        .optimize = optimize,
    });

    webui.linkLibrary(civetweb_c);
    webui.linkLibrary(webui_c);

    b.installArtifact(webui);

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

    text_editor.linkLibrary(webui_c);
    text_editor.linkLibrary(civetweb_c);
    text_editor.linkSystemLibrary("pthread");
    text_editor.linkSystemLibrary("m");

    const install_text_editor = b.addInstallArtifact(text_editor, .{});

    const text_editor_step = b.step("text_editor", "build text_editor");

    text_editor_step.dependOn(&install_text_editor.step);

    const run_text_editor_cmd = b.addRunArtifact(text_editor);
    run_text_editor_cmd.setCwd(.{
        .path = "webui/examples/C/text-editor",
    });
    run_text_editor_cmd.step.dependOn(&install_text_editor.step);

    const run_text_editor_step = b.step("run_text_editor", "Run the text_editor");
    run_text_editor_step.dependOn(&run_text_editor_cmd.step);
}

fn build_c_webui(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool) *Compile {
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
        .flags = &[_][]const u8{
            "-DNO_SSL",
        },
    });

    webui_c.linkLibC();

    webui_c.addIncludePath(.{
        .path = "webui/include",
    });

    return webui_c;
}

fn build_c_civetweb(b: *Build, optimize: OptimizeMode, target: CrossTarget, is_static: bool) *Compile {
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

    civetweb_c.addCSourceFile(.{
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

    civetweb_c.linkLibC();

    if (target.os_tag == .windows) {
        civetweb_c.linkSystemLibrary("ws2_32");
    }

    civetweb_c.addIncludePath(.{
        .path = "webui/include",
    });

    return civetweb_c;
}
