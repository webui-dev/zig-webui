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

pub const Event = struct {
    window_handle: usize,
    event_type: usize,
    element: [*:0]u8,
    event_number: usize,
    bind_id: usize,

    // get window through Window
    pub fn getWindow(self: *Event) Self {
        return .{
            .window_handle = self.window_handle,
        };
    }

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

/// Create a new webui window object using a specified window number.
pub fn newWindowWithId(id: usize) Self {
    if (id == 0 or id >= WebUI.WEBUI_MAX_IDS) {
        std.log.err("id {} is illegal", .{id});
        std.os.exit(1);
    }
    return .{
        .window_handle = WebUI.webui_new_window_id(id),
    };
}

/// Get a free window number that can be used with
/// `newWindowWithId`
pub fn getNewWindowId() usize {
    return WebUI.webui_get_new_window_id();
}

/// Bind a specific html element click event with a function.
/// Empty element means all events.
/// @param element The HTML ID
/// @param func The callback function
/// @return Returns a unique bind ID.
pub fn bind(self: *Self, element: []const u8, comptime func: fn (Event) void) usize {
    const tmp_struct = struct {
        fn handle(e: [*c]WebUI.webui_event_t) callconv(.C) void {
            func(Event.convertWebUIEventT2(e.*));
        }
    };
    return WebUI.webui_bind(self.window_handle, @ptrCast(element.ptr), tmp_struct.handle);
}

/// Show a window using embedded HTML, or a file.
/// If the window is already open, it will be refreshed.
/// Returns True if showing the window is successed
pub fn show(self: *Self, content: []const u8) bool {
    return WebUI.webui_show(self.window_handle, @ptrCast(content.ptr));
}

/// Same as `show()`. But using a specific web browser
/// Returns True if showing the window is successed
pub fn showBrowser(self: *Self, content: []const u8, browser: Browsers) bool {
    return WebUI.webui_show_browser(self.window_handle, @ptrCast(content.ptr), @intFromEnum(browser));
}

/// Set the window in Kiosk mode (Full screen)
pub fn setKiosk(self: *Self, status: bool) void {
    WebUI.webui_set_kiosk(self.window_handle, status);
}

/// Wait until all opened windows get closed.
pub fn wait() void {
    WebUI.webui_wait();
}

/// Close a specific window only. The window object will still exist.
pub fn close(self: *Self) void {
    WebUI.webui_close(self.window_handle);
}

/// Close a specific window and free all memory resources.
pub fn destory(self: *Self) void {
    WebUI.webui_destroy(self.window_handle);
}

/// Close all open windows. `wait()` will return (Break)
pub fn exit() void {
    WebUI.webui_exit();
}

/// Set the web-server root folder path for a specific window.
pub fn setRootFolder(self: *Self, path: []const u8) bool {
    return WebUI.webui_set_root_folder(self.window_handle, @ptrCast(path.ptr));
}

/// Set the web-server root folder path for all windows. Should be used before `show()`.
pub fn setDefaultRootFolder(path: []const u8) bool {
    return WebUI.webui_set_default_root_folder(@ptrCast(path.ptr));
}

// TODO: webui_set_file_handler

/// Check if the specified window is still running.
pub fn isShown(self: *Self) bool {
    return WebUI.webui_is_shown(self.window_handle);
}

/// Set the maximum time in seconds to wait for the browser to start.
pub fn setTimeout(time: usize) void {
    WebUI.webui_set_timeout(time);
}

/// Set the default embedded HTML favicon.
pub fn setIcon(self: *Self, icon: []const u8, icon_type: []const u8) void {
    WebUI.webui_set_icon(self.window_handle, @ptrCast(icon.ptr), @ptrCast(icon_type));
}

/// Base64 encoding. Use this to safely send text based data to the UI. If
/// it fails it will return NULL.
pub fn encode(str: []const u8) ?[*:0]u8 {
    const ptr = WebUI.webui_encode(@ptrCast(str.ptr));
    return @ptrCast(ptr);
}

/// Base64 decoding. Use this to safely decode received Base64 text from
/// the UI. If it fails it will return NULL.
pub fn decode(str: []const u8) [*:0]u8 {
    const ptr = WebUI.webui_decode(@ptrCast(str.ptr));
    return @ptrCast(ptr);
}

// TODO: webui_free

// TODO: webui_malloc

// TODO: webui_send_raw

/// Set a window in hidden mode. Should be called before `show()`
pub fn setHide(self: *Self, status: bool) void {
    WebUI.webui_set_hide(self.window_handle, status);
}

/// Set the window size.
pub fn setSize(self: *Self, width: c_uint, height: c_uint) void {
    WebUI.webui_set_size(self.window_handle, width, height);
}

/// Set the window position.
pub fn setPosition(self: *Self, x: c_uint, y: c_uint) void {
    WebUI.webui_set_position(self.window_handle, x, y);
}

// TODO: webui_set_profile

/// Get the full current URL.
pub fn getUrl(self: *Self) [*:0]const u8 {
    const ptr = WebUI.webui_get_url(self.window_handle);
    return @ptrCast(ptr);
}

/// Allow a specific window address to be accessible from a public network
pub fn setPublic(self: *Self, status: bool) void {
    WebUI.webui_set_public(self.window_handle, status);
}

/// Navigate to a specific URL
pub fn navigate(self: *Self, url: []const u8) void {
    WebUI.webui_navigate(self.window_handle, @ptrCast(url.ptr));
}

/// Free all memory resources. Should be called only at the end.
pub fn clean() void {
    WebUI.webui_clean();
}

/// Delete all local web-browser profiles folder. It should called at the end.
pub fn deleteAllProfiles() void {
    WebUI.webui_delete_all_profiles();
}

// TODO: webui_delete_profile

/// Get the ID of the parent process (The web browser may re-create another new process).
pub fn getParentProcessId(self: *Self) usize {
    return WebUI.webui_get_parent_process_id(self.window_handle);
}

/// Get the ID of the last child process.
pub fn getChildProcessId(self: *Self) usize {
    return WebUI.webui_get_child_process_id(self.window_handle);
}

/// Set a custom web-server network port to be used by WebUI.
/// This can be useful to determine the HTTP link of `webui.js` in case
/// you are trying to use WebUI with an external web-server like NGNIX
/// @return Returns True if the port is free and usable by WebUI
pub fn wetPort(self: *Self, port: usize) bool {
    return WebUI.webui_set_port(self.window_handle, port);
}

// TODO: webui_set_tls_certificate

/// Run JavaScript without waiting for the response.
pub fn run(self: *Self, script_content: []const u8) void {
    WebUI.webui_run(self.window_handle, @ptrCast(script_content.ptr));
}

/// Run JavaScript and get the response back
/// Make sure your local buffer can hold the response.
/// @return Returns True if there is no execution error
pub fn script(self: *Self, script_content: []const u8, timeout: usize, buffer: []u8) bool {
    return WebUI.webui_script(self.window_handle, @ptrCast(script_content.ptr), timeout, @ptrCast(buffer.ptr), buffer.len);
}

/// Chose between Deno and Nodejs as runtime for .js and .ts files.
// TODO: complete this
pub fn setRuntime() void {}
