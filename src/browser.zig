const std = @import("std");
const builtin = @import("builtin");

/// Browser families supported by discovery and explicit selection.
pub const Browser = enum {
    chrome,
    firefox,
    edge,
    safari,
    chromium,
    opera,
    brave,
    vivaldi,
    epic,
    yandex,
};

pub const LaunchOptions = struct {
    browser: Browser,
    /// Full path or PATH-resolvable executable name. Null uses discovery.
    executable: ?[]const u8 = null,
    /// Additional arguments inserted before the browser URL argument.
    arguments: []const []const u8 = &.{},
};

/// PID on POSIX and a process handle on Windows.
pub const ProcessId = std.process.Child.Id;

/// Open a non-empty URL with the operating system's default handler.
pub fn openUrl(
    gpa: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
) !void {
    if (url.len == 0) return error.InvalidUrl;
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .windows => &.{ "explorer.exe", url },
        .macos => &.{ "open", url },
        else => &.{ "xdg-open", url },
    };
    if (!try commandSucceeds(gpa, io, argv))
        return error.BrowserOpenFailed;
}

/// Return whether a browser is registered or available as an executable.
pub fn browserExists(
    gpa: std.mem.Allocator,
    io: std.Io,
    selected: Browser,
) !bool {
    const executable = try resolveExecutable(gpa, io, selected) orelse
        return false;
    gpa.free(executable);
    return true;
}

/// Return the first available browser in the platform preference order.
pub fn bestBrowser(
    gpa: std.mem.Allocator,
    io: std.Io,
) !?Browser {
    for (preferredBrowsers()) |selected|
        if (try browserExists(gpa, io, selected)) return selected;
    return null;
}

pub fn launch(
    gpa: std.mem.Allocator,
    io: std.Io,
    url: []const u8,
    options: LaunchOptions,
) !std.process.Child {
    if (url.len == 0) return error.InvalidUrl;
    if (options.executable) |executable|
        if (executable.len == 0) return error.InvalidBrowserExecutable;

    const discovered = if (options.executable == null)
        try resolveExecutable(gpa, io, options.browser) orelse
            return error.BrowserNotFound
    else
        null;
    defer if (discovered) |executable| gpa.free(executable);
    const executable = options.executable orelse discovered.?;

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);
    try argv.append(gpa, executable);
    try argv.appendSlice(gpa, options.arguments);
    const app_url = switch (options.browser) {
        .firefox, .safari => null,
        else => try std.fmt.allocPrint(gpa, "--app={s}", .{url}),
    };
    defer if (app_url) |argument| gpa.free(argument);
    switch (options.browser) {
        .firefox => {
            try argv.append(gpa, "-new-window");
            try argv.append(gpa, url);
        },
        .safari => try argv.append(gpa, url),
        else => try argv.append(gpa, app_url.?),
    }

    return std.process.spawn(io, .{
        .argv = argv.items,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
}

fn commandSucceeds(
    gpa: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
) !bool {
    const result = std.process.run(gpa, io, .{
        .argv = argv,
    }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.InvalidExe => return false,
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

fn resolveExecutable(
    gpa: std.mem.Allocator,
    io: std.Io,
    selected: Browser,
) !?[]u8 {
    return switch (builtin.os.tag) {
        .windows => resolveWindowsExecutable(gpa, io, selected),
        .macos => resolveMacosExecutable(gpa, io, selected),
        else => for (linuxExecutables(selected)) |executable| {
            if (try commandSucceeds(gpa, io, &.{ executable, "--version" }))
                break try gpa.dupe(u8, executable);
        } else null,
    };
}

fn resolveWindowsExecutable(
    gpa: std.mem.Allocator,
    io: std.Io,
    selected: Browser,
) !?[]u8 {
    const executable = windowsExecutable(selected);
    if (try commandValue(gpa, io, &.{ "where.exe", executable }, null)) |path| return path;
    // ponytail: Chrome and Chromium share chrome.exe on Windows; inspect
    // installation metadata if standalone Chromium detection becomes needed.
    if (selected == .chromium) return null;

    var key_buffer: [160]u8 = undefined;
    for ([_][]const u8{ "HKCU", "HKLM" }) |root| {
        const key = try std.fmt.bufPrint(
            &key_buffer,
            "{s}\\Software\\Microsoft\\Windows\\CurrentVersion\\" ++
                "App Paths\\{s}",
            .{ root, executable },
        );
        if (try commandValue(gpa, io, &.{
            "reg.exe",
            "query",
            key,
            "/ve",
        }, "REG_SZ")) |path| return path;
    }
    return null;
}

fn resolveMacosExecutable(
    gpa: std.mem.Allocator,
    io: std.Io,
    selected: Browser,
) !?[]u8 {
    for ([_][]const u8{ "/Applications", "/System/Applications" }) |root| {
        const path = try std.fmt.allocPrint(
            gpa,
            "{s}/{s}.app/Contents/MacOS/{s}",
            .{
                root,
                macosApplication(selected),
                macosExecutable(selected),
            },
        );
        std.Io.Dir.accessAbsolute(io, path, .{ .execute = true }) catch |err| {
            gpa.free(path);
            switch (err) {
                error.FileNotFound,
                error.NotDir,
                error.AccessDenied,
                error.PermissionDenied,
                => continue,
                else => return err,
            }
        };
        return path;
    }
    return null;
}

fn commandValue(
    gpa: std.mem.Allocator,
    io: std.Io,
    argv: []const []const u8,
    marker: ?[]const u8,
) !?[]u8 {
    const result = std.process.run(gpa, io, .{
        .argv = argv,
        .stdout_limit = .limited(64 << 10),
        .stderr_limit = .limited(64 << 10),
    }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.InvalidExe => return null,
        else => return err,
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return null,
        else => return null,
    }
    const value = parseCommandValue(result.stdout, marker) orelse return null;
    return gpa.dupe(u8, value);
}

fn parseCommandValue(
    output: []const u8,
    marker: ?[]const u8,
) ?[]const u8 {
    const value = if (marker) |needle| blk: {
        const start = std.mem.indexOf(u8, output, needle) orelse
            return null;
        break :blk output[start + needle.len ..];
    } else blk: {
        var lines = std.mem.tokenizeAny(u8, output, "\r\n");
        break :blk lines.next() orelse return null;
    };
    const trimmed = std.mem.trim(u8, value, " \t\r\n\"");
    if (trimmed.len == 0) return null;
    return trimmed;
}

fn windowsExecutable(selected: Browser) []const u8 {
    return switch (selected) {
        .chrome => "chrome.exe",
        .firefox => "firefox.exe",
        .edge => "msedge.exe",
        .safari => "Safari.exe",
        .chromium => "chromium.exe",
        .opera => "opera.exe",
        .brave => "brave.exe",
        .vivaldi => "vivaldi.exe",
        .epic => "epic.exe",
        .yandex => "browser.exe",
    };
}

fn macosApplication(selected: Browser) []const u8 {
    return switch (selected) {
        .chrome => "Google Chrome",
        .firefox => "Firefox",
        .edge => "Microsoft Edge",
        .safari => "Safari",
        .chromium => "Chromium",
        .opera => "Opera",
        .brave => "Brave Browser",
        .vivaldi => "Vivaldi",
        .epic => "Epic",
        .yandex => "Yandex",
    };
}

fn macosExecutable(selected: Browser) []const u8 {
    return switch (selected) {
        .firefox => "firefox",
        else => macosApplication(selected),
    };
}

fn linuxExecutables(selected: Browser) []const []const u8 {
    return switch (selected) {
        .chrome => &.{ "google-chrome", "google-chrome-stable" },
        .firefox => &.{"firefox"},
        .edge => &.{
            "microsoft-edge-stable",
            "microsoft-edge-beta",
            "microsoft-edge-dev",
        },
        .safari => &.{},
        .chromium => &.{ "chromium-browser", "chromium" },
        .opera => &.{"opera"},
        .brave => &.{
            "brave",
            "brave-browser",
            "brave-browser-stable",
            "brave-browser-nightly",
            "brave-browser-beta",
        },
        .vivaldi => &.{ "vivaldi", "vivaldi-stable", "vivaldi-snapshot" },
        .epic => &.{"epic"},
        .yandex => &.{"yandex-browser"},
    };
}

fn preferredBrowsers() []const Browser {
    return switch (builtin.os.tag) {
        .windows => &.{
            .chrome,
            .edge,
            .epic,
            .vivaldi,
            .brave,
            .firefox,
            .yandex,
            .chromium,
            .opera,
            .safari,
        },
        else => &.{
            .chrome,
            .edge,
            .chromium,
            .epic,
            .vivaldi,
            .brave,
            .firefox,
            .yandex,
            .opera,
            .safari,
        },
    };
}

test "browser candidates and preference order cover every browser" {
    try std.testing.expectError(
        error.InvalidUrl,
        openUrl(std.testing.allocator, std.testing.io, ""),
    );
    try std.testing.expectEqualStrings(
        "chrome.exe",
        windowsExecutable(.chrome),
    );
    try std.testing.expectEqualStrings(
        "Google Chrome",
        macosApplication(.chrome),
    );
    try std.testing.expectEqualStrings("firefox", macosExecutable(.firefox));
    try std.testing.expectEqualStrings(
        "google-chrome",
        linuxExecutables(.chrome)[0],
    );
    try std.testing.expectEqualStrings(
        "C:\\Browser\\browser.exe",
        parseCommandValue(
            "key\r\n  (Default)  REG_SZ  C:\\Browser\\browser.exe\r\n",
            "REG_SZ",
        ).?,
    );
    try std.testing.expectEqualStrings(
        "/usr/bin/browser",
        parseCommandValue("/usr/bin/browser\r\n", null).?,
    );

    var seen: std.EnumSet(Browser) = .initEmpty();
    for (preferredBrowsers()) |selected| {
        try std.testing.expect(!seen.contains(selected));
        seen.insert(selected);
    }
    try std.testing.expectEqual(
        std.meta.fields(Browser).len,
        seen.count(),
    );
    try std.testing.expectEqual(Browser.chrome, preferredBrowsers()[0]);

    if (builtin.os.tag == .linux) {
        try std.testing.expect(try commandSucceeds(
            std.testing.allocator,
            std.testing.io,
            &.{"/bin/true"},
        ));
        try std.testing.expect(!try commandSucceeds(
            std.testing.allocator,
            std.testing.io,
            &.{"/bin/false"},
        ));
        try std.testing.expect(!try commandSucceeds(
            std.testing.allocator,
            std.testing.io,
            &.{"/definitely/missing/browser"},
        ));
        if (try bestBrowser(std.testing.allocator, std.testing.io)) |selected|
            try std.testing.expect(try browserExists(
                std.testing.allocator,
                std.testing.io,
                selected,
            ));
    }
}
