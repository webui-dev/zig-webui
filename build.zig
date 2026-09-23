const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const CrossTarget = std.Target.Query;
const Compile = Build.Step.Compile;
const Module = Build.Module;
const builtin = @import("builtin");
const current_zig = builtin.zig_version;

const min_zig_string = "0.16.0";
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

pub const EmbedDirOptions = struct {
    /// Existing directory relative to the calling project's build root.
    path: []const u8,
    /// Import added to the supplied module. Use distinct names for multiple directories.
    import_name: []const u8 = "embedded_assets",
};

/// Recursively embed regular files in an existing source directory.
/// The directory is scanned during build configuration, so it must already exist.
/// Symlinks are skipped. Keys use '/' separators and are sorted bytewise.
pub fn addEmbeddedDir(b: *Build, module: *Module, options: EmbedDirOptions) !void {
    const io = b.graph.io;
    const root = if (comptime builtin.zig_version.minor >= 17)
        b.root.root_dir.handle
    else
        b.build_root.handle;
    var dir = try root.openDir(io, options.path, .{ .iterate = true });
    defer dir.close(io);

    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(b.allocator);
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const path = b.dupe(entry.path);
        if (builtin.os.tag == .windows) {
            for (path) |*char| {
                if (char.* == '\\') char.* = '/';
            }
        }
        try files.append(b.allocator, path);
    }
    std.mem.sort([]const u8, files.items, {}, struct {
        fn lessThan(_: void, a: []const u8, c: []const u8) bool {
            return std.mem.lessThan(u8, a, c);
        }
    }.lessThan);

    const generated = b.addWriteFiles();
    var source: std.Io.Writer.Allocating = .init(b.allocator);
    defer source.deinit();
    const writer = &source.writer;
    try writer.writeAll("pub const files = [_][]const u8{\n");
    for (files.items) |path| {
        try writer.print("    \"{f}\",\n", .{std.zig.fmtString(path)});
    }
    try writer.writeAll("};\npub const map = [_]struct { []const u8, []const u8 }{\n");
    for (files.items, 0..) |path, index| {
        // Numeric cache paths cannot collide with the source or require escaping.
        const cached_path = b.fmt("files/{d}", .{index});
        _ = generated.addCopyFile(b.path(b.pathJoin(&.{ options.path, path })), cached_path);
        try writer.print("    .{{ \"{f}\", @embedFile(\"{s}\") }},\n", .{
            std.zig.fmtString(path), cached_path,
        });
    }
    try writer.writeAll("};\n");
    module.addImport(options.import_name, b.createModule(.{
        .root_source_file = generated.add("embedded_assets.zig", source.written()),
    }));
}

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

    // Tuple-synthesis helper (uses the `@Tuple` builtin available on 0.16+).
    const tuple_module = b.addModule("tuple", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "tuple.zig" })),
    });

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
        .imports = &.{
            .{ .name = "flags", .module = flags_module },
            .{ .name = "tuple", .module = tuple_module },
        },
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
        .tuple_module = tuple_module,
    });

    buildTests(b, .{
        .optimize = optimize,
        .target = target,
        .webui_module = webui_module,
        .webui_artifact = webui.artifact("webui"),
        .flags_module = flags_module,
        .tuple_module = tuple_module,
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
    tuple_module: *Module,
};

const BuildTestsOptions = struct {
    optimize: OptimizeMode,
    target: Build.ResolvedTarget,
    webui_module: *Module,
    webui_artifact: *Compile,
    flags_module: *Module,
    tuple_module: *Module,
};

// ========== Helper Functions ==========

/// Create an object artifact.
fn createObject(
    b: *Build,
    name: []const u8,
    root_source: Build.LazyPath,
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
) *Compile {
    return b.addObject(.{
        .name = name,
        .root_module = b.addModule(name, .{
            .root_source_file = root_source,
            .target = target,
            .optimize = optimize,
        }),
    });
}

/// Create an executable artifact.
fn createExecutable(
    b: *Build,
    name: []const u8,
    root_source: Build.LazyPath,
    target: Build.ResolvedTarget,
    optimize: OptimizeMode,
) *Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.addModule(name, .{
            .root_source_file = root_source,
            .target = target,
            .optimize = optimize,
        }),
    });
}

// ========== Tests ==========

fn buildTests(b: *Build, options: BuildTestsOptions) void {
    const tests_path = b.path(b.pathJoin(&.{ "src", "tests.zig" }));

    const tests = b.addTest(.{
        .name = "webui-tests",
        .root_module = b.createModule(.{
            .root_source_file = tests_path,
            .target = options.target,
            .optimize = options.optimize,
        }),
    });

    tests.root_module.addImport("webui", options.webui_module);
    tests.root_module.addImport("flags", options.flags_module);
    tests.root_module.addImport("tuple", options.tuple_module);
    tests.root_module.linkLibrary(options.webui_artifact);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
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
    webui_lib.root_module.addImport("tuple", options.tuple_module);

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
    const build_all_step = b.step("examples", "build all examples");
    const examples_path = "examples";
    if (comptime builtin.zig_version.minor >= 17) {
        // Zig 0.17+: build_root is removed.
        const io = b.graph.io;
        var examples_dir = b.root.root_dir.handle.openDir(io, examples_path, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.FileNotFound => return,
                else => return err,
            }
        };
        defer examples_dir.close(io);

        var iter = examples_dir.iterate();
        while (try iter.next(io)) |entry| {
            if (entry.kind != .directory) continue;
            try buildExample(b, entry.name, options, build_all_step);
        }
    } else {
        // Zig 0.16: build_root.handle is std.Io.Dir and requires an `io`.
        const io = b.graph.io;
        var examples_dir = b.build_root.handle.openDir(io, examples_path, .{ .iterate = true }) catch |err| {
            switch (err) {
                error.FileNotFound => return,
                else => return err,
            }
        };
        defer examples_dir.close(io);

        var iter = examples_dir.iterate();
        while (try iter.next(io)) |entry| {
            if (entry.kind != .directory) continue;
            try buildExample(b, entry.name, options, build_all_step);
        }
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
    if (std.mem.eql(u8, example_name, "embedded_folder")) {
        try addEmbeddedDir(b, exe.root_module, .{
            .path = "examples/embedded_folder/assets",
        });
    }

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
