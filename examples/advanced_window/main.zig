const std = @import("std");
const webui = @import("webui");
const builtin = @import("builtin");

pub fn main() !void {
    const window = webui.newWindow();

    // Set window properties before showing
    window.setSize(1024, 768);
    window.setMinimumSize(640, 480);
    window.setPosition(100, 100);

    // Enable high contrast support
    window.setHighContrast(true);

    // Check if high contrast is enabled system-wide
    const high_contrast = webui.isHighConstrast();
    std.debug.print("System high contrast: {}\n", .{high_contrast});

    // Set window to be hidden initially (uncomment to test)
    // window.setHide(true);

    // Set connection timeout (0 means wait forever)
    webui.setTimeout(30); // 30 seconds timeout

    // Set window icon (raw SVG string)
    const icon_svg = 
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"16\" height=\"16\" viewBox=\"0 0 16 16\">" ++
        "<circle cx=\"8\" cy=\"8\" r=\"8\" fill=\"#4285F4\"/></svg>";
    window.setIcon(icon_svg, "image/svg+xml");

    // Bind window control events
    _ = try window.bind("center_window", centerWindow);
    _ = try window.bind("toggle_hide", toggleHide);
    _ = try window.bind("resize_window", resizeWindow);
    _ = try window.bind("move_window", moveWindow);
    _ = try window.bind("get_mime", getMimeType);
    _ = try window.bind("get_port", getPortInfo);
    _ = try window.bind("get_process", getProcessInfo);
    _ = try window.bind("destroy_window", destroyWindow);

    // Show the window
    try window.show("index.html");

    // Wait for window to close
    webui.wait();

    // Clean up
    webui.clean();
}

fn centerWindow(e: *webui.Event) void {
    const window = e.getWindow();
    window.setCenter();
    e.returnString("Window centered");
}

fn toggleHide(e: *webui.Event) void {
    const window = e.getWindow();
    const hide = e.getBool();
    if (hide) {
        // 使用 WebUI API 最小化窗口，避免触发 wait() 返回
        window.minimize();
        e.returnString("Window minimized");
    } else {
        // 使用 WebUI API 最大化/还原窗口
        window.maximize();
        e.returnString("Window maximized");
    }
}

fn resizeWindow(e: *webui.Event) void {
    const window = e.getWindow();
    const width = e.getIntAt(0);
    const height = e.getIntAt(1);

    if (width > 0 and height > 0) {
        window.setSize(@intCast(width), @intCast(height));
        e.returnString("Window resized");
    } else {
        e.returnString("Invalid dimensions");
    }
}

fn moveWindow(e: *webui.Event) void {
    const window = e.getWindow();
    const x = e.getIntAt(0);
    const y = e.getIntAt(1);

    if (x >= 0 and y >= 0) {
        window.setPosition(@intCast(x), @intCast(y));
        e.returnString("Window moved");
    } else {
        e.returnString("Invalid position");
    }
}

fn getMimeType(e: *webui.Event) void {
    const filename = e.getString();
    const mime = webui.getMimeType(filename);
    e.returnString(mime);
}

fn getPortInfo(e: *webui.Event) void {
    const window = e.getWindow();

    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const port = window.getPort() catch 0;
    const free_port = webui.getFreePort();

    writer.print("Current port: {}\nFree port available: {}", .{ port, free_port }) catch {};

    const written = fbs.getWritten();
    var null_terminated: [257]u8 = undefined;
    @memcpy(null_terminated[0..written.len], written);
    null_terminated[written.len] = 0;

    e.returnString(null_terminated[0..written.len :0]);
}

fn getProcessInfo(e: *webui.Event) void {
    const window = e.getWindow();

    var buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    const parent_pid = window.getParentProcessId() catch 0;
    const child_pid = window.getChildProcessId() catch 0;

    writer.print("Parent PID: {}\nChild PID: {}\n", .{ parent_pid, child_pid }) catch {};

    // On Windows, also get HWND
    if (builtin.os.tag == .windows) {
        if (window.win32GetHwnd()) |hwnd| {
            writer.print("Window HWND: {}", .{@intFromPtr(hwnd)}) catch {};
        } else |_| {
            // HWND not available
        }
    }

    const written = fbs.getWritten();
    var null_terminated: [513]u8 = undefined;
    @memcpy(null_terminated[0..written.len], written);
    null_terminated[written.len] = 0;

    e.returnString(null_terminated[0..written.len :0]);
}

fn destroyWindow(e: *webui.Event) void {
    const window = e.getWindow();
    window.close();
    e.returnString("Window closed");
}
