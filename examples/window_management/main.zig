//! WebUI Zig - Window Management Example
//! This example demonstrates various window management features
const std = @import("std");
const webui = @import("webui");

const html = @embedFile("index.html");

pub fn main() !void {
    // 配置WebUI全局设置以避免安全警告
    webui.setConfig(.show_wait_connection, true);
    webui.setConfig(.use_cookies, true);
    webui.setConfig(.multi_client, false); // 单客户端模式更安全

    // Create multiple windows
    var main_window = webui.newWindow();
    var second_window = webui.newWindow();

    // Configure main window
    main_window.setSize(800, 600);
    main_window.setPosition(100, 100);
    main_window.setCenter();
    main_window.setIcon("<svg>...</svg>", "image/svg+xml");

    // Configure second window
    second_window.setSize(400, 300);
    second_window.setPosition(500, 200);
    second_window.setKiosk(false);
    second_window.setResizable(true);

    // Bind window control functions
    _ = try main_window.binding("close_window", closeWindow);
    _ = try main_window.binding("toggle_kiosk", toggleKiosk);
    _ = try main_window.binding("get_window_info", getWindowInfo);
    _ = try main_window.binding("open_second_window", openSecondWindow);
    _ = try main_window.binding("set_window_size", setWindowSize);
    _ = try main_window.binding("center_window", centerWindow);
    _ = try main_window.binding("show_browser_info", showBrowserInfo);

    // Bind second window controls
    _ = try second_window.binding("close_second", closeSecondWindow);

    // Show main window
    // 使用普通浏览器模式
    try main_window.show(html);

    // Wait for all windows to close
    webui.wait();

    // Clean up
    webui.clean();
}

var main_win: ?webui = null;
var second_win: ?webui = null;
var is_kiosk = false;

fn closeWindow(e: *webui.Event) void {
    const win = e.getWindow();
    win.close();
    std.debug.print("Window closed\n", .{});
}

fn toggleKiosk(e: *webui.Event) void {
    // 使用WebUI原生API设置kiosk模式
    const win = e.getWindow();
    is_kiosk = !is_kiosk;
    win.setKiosk(is_kiosk);

    const response = if (is_kiosk) "Kiosk mode enabled" else "Kiosk mode disabled";
    e.returnString(response);
    std.debug.print("Kiosk mode toggled: {}\n", .{is_kiosk});
}

fn getWindowInfo(e: *webui.Event) void {
    const win = e.getWindow();

    const port = win.getPort() catch 0;
    const url = win.getUrl() catch "";
    const is_shown = win.isShown();

    var buffer: [512]u8 = undefined;
    const info = std.fmt.bufPrint(buffer[0..], "Port: {}, URL: {s}, Shown: {}", .{ port, url, is_shown }) catch "";

    // 确保有足够空间容纳null终止符
    if (info.len < buffer.len) {
        buffer[info.len] = 0;
        e.returnString(buffer[0..info.len :0]);
    } else {
        // 如果缓冲区太小，返回错误信息
        const error_msg = "Buffer too small";
        e.returnString(error_msg);
    }
    std.debug.print("Window info: {s}\n", .{info});
}

fn openSecondWindow(e: *webui.Event) void {
    // 检查第二个窗口是否存在且仍在运行
    if (second_win == null or (second_win != null and !second_win.?.isShown())) {
        // 如果窗口已经被外部关闭，重置为null
        if (second_win != null and !second_win.?.isShown()) {
            std.debug.print("Detected second window was closed externally, resetting\n", .{});
            second_win = null;
        }

        second_win = webui.newWindow();
        if (second_win) |*win| {
            // 重新绑定第二个窗口的关闭函数
            _ = win.binding("close_second", closeSecondWindow) catch {
                std.debug.print("Failed to bind close_second function\n", .{});
                e.returnString("Failed to bind second window functions");
                return;
            };

            // 绑定空的断开连接事件处理器，用于清理状态
            _ = win.binding("", handleSecondWindowDisconnect) catch {
                std.debug.print("Failed to bind disconnect handler\n", .{});
            };

            win.setSize(400, 300);
            win.show("<html><head><script src=\"/webui.js\"></script></head><body><h1>Second Window</h1><button onclick=\"close_second()\">Close</button></body></html>") catch {
                std.debug.print("Failed to show second window\n", .{});
                e.returnString("Failed to show second window");
                return;
            };
            e.returnString("Second window opened successfully");
        } else {
            e.returnString("Failed to create second window");
        }
    } else {
        e.returnString("Second window already open");
    }
}

fn closeSecondWindow(e: *webui.Event) void {
    const win = e.getWindow();
    win.close();
    second_win = null;
    std.debug.print("Second window closed\n", .{});
}

fn handleSecondWindowDisconnect(e: *webui.Event) void {
    // 当第二个窗口断开连接时（包括用户点击x关闭），清理状态
    _ = e; // 标记参数已使用
    second_win = null;
    std.debug.print("Second window disconnected\n", .{});
}

fn setWindowSize(e: *webui.Event, width: i64, height: i64) void {
    const win = e.getWindow();
    win.setSize(@intCast(width), @intCast(height));

    var buffer: [128]u8 = undefined;
    const response = std.fmt.bufPrint(buffer[0..], "Size set to {}x{}", .{ width, height }) catch "";

    // 确保有足够空间容纳null终止符
    if (response.len < buffer.len) {
        buffer[response.len] = 0;
        e.returnString(buffer[0..response.len :0]);
    } else {
        // 如果缓冲区太小，返回错误信息
        const error_msg = "Buffer too small";
        e.returnString(error_msg);
    }
    std.debug.print("Window size set to {}x{}\n", .{ width, height });
}

fn centerWindow(e: *webui.Event) void {
    const win = e.getWindow();
    win.setCenter();
    e.returnString("Window centered");
    std.debug.print("Window centered\n", .{});
}

fn showBrowserInfo(e: *webui.Event) void {
    // 显示浏览器和窗口信息
    e.runClient(
        \\const info = {
        \\    userAgent: navigator.userAgent,
        \\    screenWidth: screen.width,
        \\    screenHeight: screen.height,
        \\    windowWidth: window.innerWidth,
        \\    windowHeight: window.innerHeight,
        \\    isFullscreen: !!document.fullscreenElement
        \\};
        \\document.getElementById('info-display').innerHTML = 
        \\    'Browser: ' + info.userAgent.split(' ').pop() + '<br>' +
        \\    'Screen: ' + info.screenWidth + 'x' + info.screenHeight + '<br>' +
        \\    'Window: ' + info.windowWidth + 'x' + info.windowHeight + '<br>' +
        \\    'Fullscreen: ' + info.isFullscreen;
    );
    std.debug.print("Browser info displayed\n", .{});
    e.returnString("Browser information updated");
}
