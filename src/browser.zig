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
    pub const Size = struct {
        width: u32,
        height: u32,
    };

    pub const Position = struct {
        x: i32,
        y: i32,
    };

    browser: Browser,
    /// Full path or PATH-resolvable executable name. Null uses discovery.
    executable: ?[]const u8 = null,
    /// Additional arguments inserted before the browser URL argument.
    arguments: []const []const u8 = &.{},
    /// Start in kiosk mode. Supported by Chromium-family browsers and Firefox.
    kiosk: bool = false,
    /// Initial outer window size. Supported by Chromium-family browsers.
    size: ?Size = null,
    /// Initial window position. Supported by Chromium-family browsers.
    position: ?Position = null,
    /// Force native high-contrast UI. Supported by Chromium-family browsers.
    high_contrast: bool = false,
    /// Absolute profile directory managed by this launch.
    profile: ?[]const u8 = null,
    /// Proxy server passed to Chromium-family browsers.
    proxy: ?[]const u8 = null,
};

/// PID on POSIX and a process handle on Windows.
pub const ProcessId = std.process.Child.Id;

/// Numeric ID of the process that created this one.
pub fn parentProcessId() error{ Unexpected, Unsupported }!u32 {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        var info: windows.PROCESS.BASIC_INFORMATION = undefined;
        switch (windows.ntdll.NtQueryInformationProcess(
            windows.GetCurrentProcess(),
            .BasicInformation,
            &info,
            @sizeOf(@TypeOf(info)),
            null,
        )) {
            .SUCCESS => {},
            else => |status| return windows.unexpectedStatus(status),
        }
        return @truncate(info.InheritedFromUniqueProcessId);
    }
    if (builtin.os.tag == .wasi) return error.Unsupported;
    return @intCast(std.posix.getppid());
}

/// Whether the host requests a high-contrast interface. Unreadable or absent
/// desktop settings report false instead of failing.
pub fn isHighContrast(gpa: std.mem.Allocator, io: std.Io) !bool {
    return switch (builtin.os.tag) {
        .windows => windowsHighContrast(gpa, io),
        .macos => macosHighContrast(gpa, io),
        .wasi => false,
        else => desktopHighContrast(gpa, io),
    };
}

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
    try validateLaunchOptions(options);

    const discovered = if (options.executable == null)
        try resolveExecutable(gpa, io, options.browser) orelse
            return error.BrowserNotFound
    else
        null;
    defer if (discovered) |executable| gpa.free(executable);
    const executable = options.executable orelse discovered.?;
    if (options.profile) |profile|
        try std.Io.Dir.cwd().createDirPath(io, profile);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const argv = try buildLaunchArgv(
        arena.allocator(),
        executable,
        url,
        options,
    );

    return std.process.spawn(io, .{
        .argv = argv,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
}

fn buildLaunchArgv(
    allocator: std.mem.Allocator,
    executable: []const u8,
    url: []const u8,
    options: LaunchOptions,
) ![]const []const u8 {
    try validateLaunchOptions(options);

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(allocator, executable);
    try argv.appendSlice(allocator, options.arguments);
    if (options.kiosk) try argv.append(allocator, "--kiosk");
    if (options.size) |size| try argv.append(
        allocator,
        try std.fmt.allocPrint(
            allocator,
            "--window-size={d},{d}",
            .{ size.width, size.height },
        ),
    );
    if (options.position) |position| try argv.append(
        allocator,
        try std.fmt.allocPrint(
            allocator,
            "--window-position={d},{d}",
            .{ position.x, position.y },
        ),
    );
    if (options.high_contrast)
        try argv.append(allocator, "--force-high-contrast");
    if (options.profile) |profile| switch (options.browser) {
        .firefox => {
            try argv.append(allocator, "--profile");
            try argv.append(allocator, profile);
            try argv.append(allocator, "--new-instance");
        },
        .safari => unreachable,
        else => try argv.append(
            allocator,
            try std.fmt.allocPrint(
                allocator,
                "--user-data-dir={s}",
                .{profile},
            ),
        ),
    };
    if (options.proxy) |proxy| try argv.append(
        allocator,
        try std.fmt.allocPrint(
            allocator,
            "--proxy-server={s}",
            .{proxy},
        ),
    );
    switch (options.browser) {
        .firefox => {
            try argv.append(allocator, "-new-window");
            try argv.append(allocator, url);
        },
        .safari => try argv.append(allocator, url),
        else => try argv.append(
            allocator,
            try std.fmt.allocPrint(allocator, "--app={s}", .{url}),
        ),
    }
    return argv.toOwnedSlice(allocator);
}

fn validateLaunchOptions(options: LaunchOptions) !void {
    if (options.size) |size|
        if (size.width == 0 or size.height == 0)
            return error.InvalidWindowSize;
    if (options.profile) |profile| try validateProfilePath(profile);
    if (options.proxy) |proxy|
        if (proxy.len == 0 or std.mem.indexOfScalar(u8, proxy, 0) != null)
            return error.InvalidBrowserProxy;
    switch (options.browser) {
        .firefox => {
            if (options.size != null or
                options.position != null or options.high_contrast)
                return error.UnsupportedBrowserControl;
            if (options.proxy != null) return error.UnsupportedBrowserProxy;
        },
        .safari => {
            if (options.kiosk or options.size != null or
                options.position != null or options.high_contrast)
                return error.UnsupportedBrowserControl;
            if (options.profile != null)
                return error.UnsupportedBrowserProfile;
            if (options.proxy != null) return error.UnsupportedBrowserProxy;
        },
        else => {},
    }
}

fn validateProfilePath(path: []const u8) !void {
    if (path.len == 0 or
        std.mem.indexOfScalar(u8, path, 0) != null or
        !std.fs.path.isAbsolute(path))
    {
        return error.InvalidBrowserProfile;
    }
    var components = std.mem.tokenizeAny(u8, path, "/\\");
    while (components.next()) |component|
        if (std.mem.eql(u8, component, ".") or
            std.mem.eql(u8, component, ".."))
            return error.InvalidBrowserProfile;
    const parent = std.fs.path.dirname(path) orelse
        return error.InvalidBrowserProfile;
    const grandparent = std.fs.path.dirname(parent) orelse
        return error.InvalidBrowserProfile;
    if (std.mem.eql(u8, parent, grandparent))
        return error.InvalidBrowserProfile;
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

fn windowsHighContrast(gpa: std.mem.Allocator, io: std.Io) !bool {
    const flags = (try commandValue(gpa, io, &.{
        "reg.exe",
        "query",
        "HKCU\\Control Panel\\Accessibility\\HighContrast",
        "/v",
        "Flags",
    }, "REG_SZ")) orelse return false;
    defer gpa.free(flags);
    return parseHighContrastFlags(flags);
}

/// `HCF_HIGHCONTRASTON` in the accessibility flags that `SPI_GETHIGHCONTRAST`
/// also reports.
fn parseHighContrastFlags(value: []const u8) bool {
    const flags = std.fmt.parseInt(u32, value, 10) catch return false;
    return flags & 0x01 != 0;
}

fn macosHighContrast(gpa: std.mem.Allocator, io: std.Io) !bool {
    // ponytail: upstream reads AppleInterfaceStyle, which reports dark mode
    // rather than contrast. increaseContrast is the setting the accessibility
    // pane writes. Add differentiateWithoutColor only if callers ask for it.
    for ([_][]const u8{ "increaseContrast", "whiteOnBlack" }) |key| {
        const value = (try commandValue(gpa, io, &.{
            "defaults",
            "read",
            "com.apple.universalaccess",
            key,
        }, null)) orelse continue;
        defer gpa.free(value);
        if (std.mem.eql(u8, value, "1")) return true;
    }
    return false;
}

/// Probes in order of directness. Upstream only reads the GNOME accessibility
/// toggle, so the theme-based desktops fall back to naming conventions.
/// ponytail: every miss costs one short-lived child process; cache the result
/// only if a caller polls this on a hot path.
const high_contrast_probes = [_]struct {
    argv: []const []const u8,
    /// Boolean probes must print `true`; the rest must name the theme.
    boolean: bool,
}{
    .{ .argv = &.{
        "gsettings",
        "get",
        "org.gnome.desktop.a11y.interface",
        "high-contrast",
    }, .boolean = true },
    .{ .argv = &.{
        "gsettings",
        "get",
        "org.gnome.desktop.interface",
        "gtk-theme",
    }, .boolean = false },
    .{ .argv = &.{
        "kreadconfig6",
        "--file",
        "kdeglobals",
        "--group",
        "General",
        "--key",
        "ColorScheme",
    }, .boolean = false },
    .{ .argv = &.{
        "kreadconfig5",
        "--file",
        "kdeglobals",
        "--group",
        "General",
        "--key",
        "ColorScheme",
    }, .boolean = false },
    .{ .argv = &.{
        "xfconf-query",
        "-c",
        "xsettings",
        "-p",
        "/Net/ThemeName",
    }, .boolean = false },
};

fn desktopHighContrast(gpa: std.mem.Allocator, io: std.Io) !bool {
    for (high_contrast_probes) |probe| {
        const value = (try commandValue(gpa, io, probe.argv, null)) orelse
            continue;
        defer gpa.free(value);
        const enabled = if (probe.boolean)
            std.mem.eql(u8, value, "true")
        else
            namesHighContrastTheme(value);
        if (enabled) return true;
    }
    return false;
}

/// Matches GNOME `HighContrast` and `HighContrastInverse`, KDE
/// `BreezeHighContrast`, and the spaced `High Contrast` scheme names.
fn namesHighContrastTheme(value: []const u8) bool {
    var buffer: [64]u8 = undefined;
    var len: usize = 0;
    for (value) |byte| {
        switch (byte) {
            ' ', '-', '_', '\'', '"' => continue,
            else => {},
        }
        if (len == buffer.len) break;
        buffer[len] = std.ascii.toLower(byte);
        len += 1;
    }
    return std.mem.indexOf(u8, buffer[0..len], "highcontrast") != null;
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
    return try gpa.dupe(u8, value);
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

test "typed browser launch options build supported argv" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const profile = if (builtin.os.tag == .windows)
        "C:\\tmp\\webui\\profile"
    else
        "/tmp/webui/profile";
    const profile_argument = if (builtin.os.tag == .windows)
        "--user-data-dir=C:\\tmp\\webui\\profile"
    else
        "--user-data-dir=/tmp/webui/profile";

    const chromium = try buildLaunchArgv(
        arena.allocator(),
        "/browser",
        "https://127.0.0.1/",
        .{
            .browser = .chromium,
            .arguments = &.{"--guest"},
            .kiosk = true,
            .size = .{ .width = 1280, .height = 720 },
            .position = .{ .x = -20, .y = 30 },
            .high_contrast = true,
            .profile = profile,
            .proxy = "socks5://127.0.0.1:1080",
        },
    );
    const expected_chromium: []const []const u8 = &.{
        "/browser",
        "--guest",
        "--kiosk",
        "--window-size=1280,720",
        "--window-position=-20,30",
        "--force-high-contrast",
        profile_argument,
        "--proxy-server=socks5://127.0.0.1:1080",
        "--app=https://127.0.0.1/",
    };
    try std.testing.expectEqualDeep(expected_chromium, chromium);

    const firefox = try buildLaunchArgv(
        arena.allocator(),
        "/firefox",
        "https://127.0.0.1/",
        .{
            .browser = .firefox,
            .kiosk = true,
            .profile = profile,
        },
    );
    const expected_firefox: []const []const u8 = &.{
        "/firefox",
        "--kiosk",
        "--profile",
        profile,
        "--new-instance",
        "-new-window",
        "https://127.0.0.1/",
    };
    try std.testing.expectEqualDeep(expected_firefox, firefox);

    try std.testing.expectError(
        error.InvalidWindowSize,
        buildLaunchArgv(
            arena.allocator(),
            "/browser",
            "https://127.0.0.1/",
            .{
                .browser = .chromium,
                .size = .{ .width = 0, .height = 720 },
            },
        ),
    );
    try std.testing.expectError(
        error.UnsupportedBrowserControl,
        buildLaunchArgv(
            arena.allocator(),
            "/firefox",
            "https://127.0.0.1/",
            .{
                .browser = .firefox,
                .position = .{ .x = 0, .y = 0 },
            },
        ),
    );
    try std.testing.expectError(
        error.UnsupportedBrowserProxy,
        buildLaunchArgv(
            arena.allocator(),
            "/firefox",
            "https://127.0.0.1/",
            .{
                .browser = .firefox,
                .proxy = "http://127.0.0.1:8888",
            },
        ),
    );
    try std.testing.expectError(
        error.UnsupportedBrowserProfile,
        buildLaunchArgv(
            arena.allocator(),
            "/safari",
            "https://127.0.0.1/",
            .{ .browser = .safari, .profile = profile },
        ),
    );
    try std.testing.expectError(
        error.InvalidBrowserProfile,
        buildLaunchArgv(
            arena.allocator(),
            "/browser",
            "https://127.0.0.1/",
            .{
                .browser = .chromium,
                .profile = if (builtin.os.tag == .windows) "C:\\" else "/",
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidBrowserProxy,
        buildLaunchArgv(
            arena.allocator(),
            "/browser",
            "https://127.0.0.1/",
            .{ .browser = .chromium, .proxy = "" },
        ),
    );
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

test "high contrast settings parse across desktops" {
    for ([_][]const u8{
        "HighContrast",
        "'HighContrastInverse'",
        "Breeze High Contrast",
        "highcontrast-dark",
    }) |value|
        try std.testing.expect(namesHighContrastTheme(value));
    for ([_][]const u8{ "Adwaita", "Breeze", "Contrast", "'adw-gtk3'", "" }) |value|
        try std.testing.expect(!namesHighContrastTheme(value));

    try std.testing.expect(parseHighContrastFlags("127"));
    try std.testing.expect(parseHighContrastFlags("1"));
    try std.testing.expect(!parseHighContrastFlags("126"));
    try std.testing.expect(!parseHighContrastFlags("0"));
    try std.testing.expect(!parseHighContrastFlags(""));
    try std.testing.expect(!parseHighContrastFlags("0x1"));
}

test "host high contrast probe reports a value" {
    // Absent desktop tooling must report false rather than fail.
    _ = try isHighContrast(std.testing.allocator, std.testing.io);
}

test "parent process id names a real process" {
    const parent = try parentProcessId();
    try std.testing.expect(parent != 0);
    // ponytail: the Windows path only runs on Windows, so a native test can
    // check the POSIX path directly and the rest through the zero check.
    if (builtin.os.tag != .windows and builtin.os.tag != .wasi)
        try std.testing.expectEqual(std.posix.getppid(), @as(
            std.posix.pid_t,
            @intCast(parent),
        ));
}
