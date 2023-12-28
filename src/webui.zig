const std = @import("std");

const WebUI = @cImport({
    @cInclude("webui.h");
});

const Self = @This();

const Browsers = enum(u8) {
    NoBrowser = 0, // 0. No web browser
    AnyBrowser, // 1. Default recommended web browser
    Chrome, // 2. Google Chrome
    Firefox, // 3. Mozilla Firefox
    Edge, // 4. Microsoft Edge
    Safari, // 5. Apple Safari
    Chromium, // 6. The Chromium Project
    Opera, // 7. Opera Browser
    Brave, // 8. The Brave Browser
    Vivaldi, // 9. The Vivaldi Browser
    Epic, // 10. The Epic Browser
    Yandex, // 11. The Yandex Browser
    ChromiumBased,
};

const Runtimes = enum(u8) {
    None = 0, // 0. Prevent WebUI from using any runtime for .js and .ts files
    Deno, // 1. Use Deno runtime for .js and .ts files
    NodeJS, // 2. Use Nodejs runtime for .js files
};

const Events = enum(u8) {
    EVENT_DISCONNECTED = 0, // 0. Window disconnection event
    EVENT_CONNECTED, // 1. Window connection event
    EVENT_MOUSE_CLICK, // 2. Mouse click event
    EVENT_NAVIGATION, // 3. Window navigation event
    EVENT_CALLBACK, // 4. Function call event
};

const Event = struct {
    window_handle: usize,
    event_type: usize,
    element: [*:0]u8,
    event_number: usize,
    bind_id: usize,

    pub fn convetToWebUIEventT(self: *Event) WebUI.webui_event_t {
        return WebUI.webui_event_t{
            .window = self.window_handle,
            .event_type = self.event_type,
            .element = @ptrCast(self.element),
            .event_number = self.event_number,
            .bind_id = self.bind_id,
        };
    }

    pub fn convertWebUIEventT2(event: WebUI.webui_event_t) Event {
        return .{
            .window_handle = event.window,
            .event_type = event.event_type,
            .element = @ptrCast(event.element),
            .event_number = event.event_number,
            .bind_id = event.bind_id,
        };
    }
};

window_handle: usize,

/// Creating a new WebUI window object.
pub fn newWindow() Self {
    return .{
        .window_handle = WebUI.webui_new_window(),
    };
}

/// Show Window
/// You can show the WebUI window, which is a web browser window.
/// If the window is already shown, the UI will get refreshed by the new content in the same window.
pub fn show(self: *Self, content: []const u8) bool {
    return WebUI.webui_show(self.window_handle, @ptrCast(content.ptr));
}

/// To know if a specific window is running.
pub fn isShown(self: *Self) bool {
    return WebUI.webui_is_shown(self.window_handle);
}

/// To embed an icon (String format) whtin the application.
pub fn setIcon(self: *Self, icon: []const u8, icon_type: []const u8) void {
    WebUI.webui_set_icon(self.window_handle, @ptrCast(icon.ptr), @ptrCast(icon_type));
}

/// bind event handle to element
pub fn bind(self: *Self, element: []const u8, func: *const fn (Event) void) void {
    const tmp_struct = struct {
        fn handle(e: [*c]WebUI.webui_event_t) callconv(.C) void {
            func(Event.convertWebUIEventT2(e.*));
        }
    };
    WebUI.webui_bind(self.window_handle, @ptrCast(element.ptr), tmp_struct.handle);
}

/// It is essential to call the wait function at the end of your primary function after you create/show all your windows.
/// This will make your application run until the user closes all visible windows or when calling exit().
/// You can show again the same windows, create a new one, or call the wait function again.
pub fn wait() void {
    WebUI.webui_wait();
}

/// You can call exit at any moment, which tries to close all opened windows and make wait break.
/// All WebUI memory resources will be freed, which makes WebUI unusable.
pub fn exit() void {
    WebUI.webui_exit();
}

// TODO: webui_set_file_handler

/// You can call close to close a specific window, if there is no running window left wait will break.
pub fn close(self: *Self) void {
    WebUI.webui_close(self.window_handle);
}

/// WebUI waits a couple of seconds (Default is 30 seconds) to let the web browser start and connect.
/// You can control this behavior by using timeout.
pub fn setTimeout(time: usize) void {
    WebUI.webui_set_timeout(time);
}

/// run js script and wait some time for response
pub fn script(self: *Self, script_content: []const u8, timeout: usize, buffer: []u8) bool {
    return WebUI.webui_script(self.window_handle, @ptrCast(script_content.ptr), timeout, @ptrCast(buffer.ptr), buffer.len);
}

/// quick run script and ignore response
pub fn run(self: *Self, script_content: []const u8) void {
    WebUI.webui_run(self.window_handle, @ptrCast(script_content.ptr));
}
