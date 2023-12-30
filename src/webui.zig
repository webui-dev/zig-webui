// TODO: c_longlong
const std = @import("std");
const flags = @import("flags");

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

/// get the string length
/// @param: str [*c]const u8
pub fn str_len(str: anytype) usize {
    const t = @TypeOf(str);
    switch (t) {
        [*c]u8, [*c]const u8, [*:0]u8, [*:0]const u8 => {
            return std.mem.len(str);
        },
        else => {
            @compileError("type is incorrect");
        },
    }
}

pub const Event = struct {
    window_handle: usize,
    event_type: usize,
    element: []u8,
    event_number: usize,
    bind_id: usize,

    e: *WebUI.webui_event_t,

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
            .element = @ptrCast(self.element.ptr),
            .event_number = self.event_number,
            .bind_id = self.bind_id,
        };
    }

    pub fn convertWebUIEventT2(event: *WebUI.webui_event_t) Event {
        const len = str_len(event.element);

        return .{
            .window_handle = event.window,
            .event_type = event.event_type,
            .element = event.element[0..len],
            .event_number = event.event_number,
            .bind_id = event.bind_id,
            .e = event,
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
pub fn bind(self: *Self, element: []const u8, comptime func: fn (e: Event) void) usize {
    const tmp_struct = struct {
        fn handle(tmp_e: [*c]WebUI.webui_event_t) callconv(.C) void {
            func(Event.convertWebUIEventT2(tmp_e));
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

/// Set a custom handler to serve files.
pub fn setFileHandler(self: *Self, comptime handler: fn (filename: []const u8) []u8) void {
    const tmp_struct = struct {
        fn handle(tmp_filename: [*c]const u8, length: [*c]c_int) callconv(.C) ?*const anyopaque {
            const len = str_len(tmp_filename);
            const content = handler(tmp_filename[0..len]);
            length.* = @intCast(content.len);
            return @ptrCast(content.ptr);
        }
    };
    WebUI.webui_set_file_handler(self.window_handle, tmp_struct.handle);
}

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
pub fn encode(str: []const u8) ?[]u8 {
    const ptr = WebUI.webui_encode(@ptrCast(str.ptr));
    if (ptr == null) {
        return null;
    }
    const len = str_len(ptr);
    return ptr[0..len];
}

/// Base64 decoding. Use this to safely decode received Base64 text from
/// the UI. If it fails it will return NULL.
pub fn decode(str: []const u8) ?[]u8 {
    const ptr = WebUI.webui_decode(@ptrCast(str.ptr));
    if (ptr == null) {
        return null;
    }
    const len = str_len(ptr);
    return ptr[0..len];
}

/// Safely free a buffer allocated by WebUI using
pub fn free(buf: []u8) void {
    WebUI.webui_free(@ptrCast(buf.ptr));
}

/// Safely allocate memory using the WebUI memory management system
/// it can be safely freed using `free()` at any time.
pub fn malloc(size: usize) []u8 {
    const ptr = WebUI.webui_malloc(size);
    return @as([*]u8, @ptrCast(ptr))[0..size];
}

/// Safely send raw data to the UI.
pub fn sendRaw(self: *Self, js_func: []const u8, raw: []u8) void {
    WebUI.webui_send_raw(self.window_handle, @ptrCast(js_func.ptr), @ptrCast(raw.ptr), raw.len);
}

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

/// Set the web browser profile to use. An empty `name` and `path` means
/// the default user profile. Need to be called before `show()`.
pub fn setProfile(self: *Self, name: []const u8, path: []const u8) void {
    WebUI.webui_set_profile(self.window_handle, @ptrCast(name.ptr), @ptrCast(path.ptr));
}

/// Get the full current URL.
pub fn getUrl(self: *Self) []const u8 {
    const ptr = WebUI.webui_get_url(self.window_handle);
    const len = str_len(ptr);
    return ptr[0..len];
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

/// Delete a specific window web-browser local folder profile.
pub fn deleteProfile(self: *Self) void {
    WebUI.webui_delete_profile(self.window_handle);
}

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

/// Set the SSL/TLS certificate and the private key content, both in PEM
/// format. This works only with `webui-2-secure` library. If set empty WebUI
/// will generate a self-signed certificate.
pub fn setTlsCertificate(certificate_pem: []const u8, private_key_pem: []const u8) bool {
    return WebUI.webui_set_tls_certificate(@ptrCast(certificate_pem.ptr), @ptrCast(private_key_pem.ptr));
}

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
pub fn setRuntime(self: *Self, runtime: Runtimes) void {
    WebUI.webui_set_runtime(self.window_handle, @intFromEnum(runtime));
}

/// Get an argument as integer at a specific index
pub fn getIntAt(e: Event, index: usize) c_longlong {
    return WebUI.webui_get_int_at(e.e, index);
}

/// Get the first argument as integer
pub fn getInt(e: Event) c_longlong {
    return WebUI.webui_get_int(e.e);
}

/// Get an argument as string at a specific index
pub fn getStringAt(e: Event, index: usize) [*c]const u8 {
    const ptr = WebUI.webui_get_string_at(e.e, index);
    return ptr;
}

/// Get the first argument as string
pub fn getString(e: Event) [*c]const u8 {
    const ptr = WebUI.webui_get_string(e.e);
    return ptr;
}

/// Get an argument as boolean at a specific index
pub fn getBoolAt(e: Event, index: usize) bool {
    return WebUI.webui_get_bool_at(e.e, index);
}

/// Get the first argument as boolean
pub fn getBool(e: Event) bool {
    return WebUI.webui_get_bool(e.e);
}

/// Get the size in bytes of an argument at a specific index
pub fn getSizeAt(e: Event, index: usize) usize {
    return WebUI.webui_get_size_at(e.e, index);
}

/// Get size in bytes of the first argument
pub fn getSize(e: Event) usize {
    return WebUI.webui_get_size(e.e);
}

/// Return the response to JavaScript as integer.
pub fn returnInt(e: Event, n: c_longlong) void {
    WebUI.webui_return_int(e.e, n);
}

/// Return the response to JavaScript as string.
pub fn returnString(e: Event, str: []const u8) !void {
    WebUI.webui_return_string(e.e, @ptrCast(str.ptr));
}

/// Return the response to JavaScript as boolean.
pub fn returnBool(e: Event, b: bool) void {
    WebUI.webui_return_bool(e.e, b);
}

/// Bind a specific HTML element click event with a function. Empty element means all events.
pub fn interfaceBind(self: *Self, element: []const u8, comptime callback: fn (window_handle: usize, event_type: usize, element: []u8, event_number: usize, bind_id: usize) void) void {
    const tmp_struct = struct {
        fn handle(tmp_window: usize, tmp_event_type: usize, tmp_element: [*c]u8, tmp_event_number: usize, tmp_bind_id: usize) callconv(.C) void {
            const len = str_len(tmp_element);
            callback(tmp_window, tmp_event_type, tmp_element[0..len], tmp_event_number, tmp_bind_id);
        }
    };
    WebUI.webui_interface_bind(self.window_handle, @ptrCast(element.ptr), tmp_struct.handle);
}

/// When using `interfaceBind()`, you may need this function to easily set a response.
pub fn interfaceSetResponse(self: *Self, event_number: usize, response: []const u8) void {
    WebUI.webui_interface_set_response(self.window_handle, event_number, @ptrCast(response.ptr));
}

/// Check if the app still running.
pub fn interfaceIsAppRunning() bool {
    return WebUI.webui_interface_is_app_running();
}

/// Get a unique window ID.
pub fn interfaceGetWindowId(self: *Self) usize {
    return WebUI.webui_interface_get_window_id(self.window_handle);
}

/// Get an argument as string at a specific index
pub fn interfaceGetStringAt(self: *Self, event_number: usize, index: usize) [*c]const u8 {
    const ptr = WebUI.webui_interface_get_string_at(self.window_handle, event_number, index);
    return ptr;
}

/// Get an argument as integer at a specific index
pub fn interfaceGetIntAt(self: *Self, event_number: usize, index: usize) c_longlong {
    return WebUI.webui_interface_get_int_at(self.window_handle, event_number, index);
}

/// Get an argument as boolean at a specific index
pub fn interfaceGetBoolAt(self: *Self, event_number: usize, index: usize) bool {
    return WebUI.webui_interface_get_bool_at(self.window_handle, event_number, index);
}

/// Get the size in bytes of an argument at a specific index
pub fn interfaceGetSizeAt(self: *Self, event_number: usize, index: usize) usize {
    return WebUI.webui_interface_get_size_at(self.window_handle, event_number, index);
}
