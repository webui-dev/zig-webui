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
    return switch (builtin.os.tag) {
        .windows => windowsBrowserExists(gpa, io, selected),
        .macos => commandSucceeds(gpa, io, &.{
            "open",
            "-R",
            "-a",
            macosApplication(selected),
        }),
        else => for (linuxExecutables(selected)) |executable| {
            if (try commandSucceeds(gpa, io, &.{ executable, "--version" }))
                break true;
        } else false,
    };
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

fn windowsBrowserExists(
    gpa: std.mem.Allocator,
    io: std.Io,
    selected: Browser,
) !bool {
    const executable = windowsExecutable(selected);
    if (try commandSucceeds(gpa, io, &.{ "where.exe", executable }))
        return true;
    // ponytail: Chrome and Chromium share chrome.exe on Windows; inspect
    // installation metadata if standalone Chromium detection becomes needed.
    if (selected == .chromium) return false;

    var key_buffer: [160]u8 = undefined;
    for ([_][]const u8{ "HKCU", "HKLM" }) |root| {
        const key = try std.fmt.bufPrint(
            &key_buffer,
            "{s}\\Software\\Microsoft\\Windows\\CurrentVersion\\" ++
                "App Paths\\{s}",
            .{ root, executable },
        );
        if (try commandSucceeds(gpa, io, &.{
            "reg.exe",
            "query",
            key,
            "/ve",
        })) return true;
    }
    return false;
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
    try std.testing.expectEqualStrings(
        "google-chrome",
        linuxExecutables(.chrome)[0],
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
