//! This is Zig Wrapping for [Webui](https://github.com/webui-dev/webui),
//! Zig-WebUI Library
//!
//! WebSite: [http://webui.me](http://webui.me),
//! Github: [https://github.com/webui-dev/zig-webui](https://github.com/webui-dev/zig-webui)
//!
//! Copyright (c) 2020-2024 [Jinzhongjia](https://github.com/jinzhongjia),
//! Licensed under MIT License.

const webui = @This();

const builtin = @import("builtin");
const std = @import("std");

const flags = @import("flags");

pub const c = @import("c.zig");

/// The window number. Do not modify.
window_handle: usize,

/// Creating a new WebUI window object.
pub fn newWindow() webui {
    return .{
        .window_handle = c.webui_new_window(),
    };
}

/// Create a new webui window object using a specified window number.
pub fn newWindowWithId(id: usize) webui {
    if (id == 0 or id >= WEBUI_MAX_IDS) {
        std.log.err("id {} is illegal", .{id});
        if (comptime builtin.zig_version.minor == 11) {
            std.os.exit(1);
        } else if (comptime builtin.zig_version.minor == 12) {
            std.posix.exit(1);
        }
    }
    return .{
        .window_handle = c.webui_new_window_id(id),
    };
}

/// Get a free window number that can be used with
/// `newWindowWithId`
pub fn getNewWindowId() usize {
    return c.webui_get_new_window_id();
}

/// Bind an HTML element and a JavaScript object with a backend function.
/// Empty element name means all events.
/// `element` The HTML element / JavaScript object
/// `func` is The callback function,
/// Returns a unique bind ID.
pub fn bind(
    self: webui,
    element: [:0]const u8,
    comptime func: fn (e: *Event) void,
) usize {
    const tmp_struct = struct {
        fn handle(tmp_e: *Event) callconv(.C) void {
            func(tmp_e);
        }
    };
    return c.webui_bind(self.window_handle, element.ptr, tmp_struct.handle);
}

/// Get the recommended web browser ID to use. If you
/// are already using one, this function will return the same ID.
pub fn getBestBrowser(self: webui) Browser {
    return c.webui_get_best_browser(self.window_handle);
}

/// Show a window using embedded HTML, or a file.
/// If the window is already open, it will be refreshed.
/// This will refresh all windows in multi-client mode.
/// Returns True if showing the window is successed
/// `content` is the html which will be shown
pub fn show(self: webui, content: [:0]const u8) bool {
    return c.webui_show(self.window_handle, content.ptr);
}

/// Same as `show()`. But using a specific web browser
/// Returns True if showing the window is successed
pub fn showBrowser(self: webui, content: [:0]const u8, browser: Browser) bool {
    return c.webui_show_browser(self.window_handle, content.ptr, browser);
}

/// Same as `show()`. But start only the web server and return the URL.
/// No window will be shown.
pub fn startServer(self: webui, path: [:0]const u8) [:0]const u8 {
    const url = c.webui_start_server(self.window_handle, path.ptr);
    const url_len = std.mem.len(url);
    return url[0..url_len :0];
}

/// Show a WebView window using embedded HTML, or a file. If the window is already
/// opend, it will be refreshed. Note: Win32 need `WebView2Loader.dll`.
/// Returns True if if showing the WebView window is successed.
pub fn showWv(self: webui, content: [:0]const u8) bool {
    return c.webui_show_wv(self.window_handle, content.ptr);
}

/// Set the window in Kiosk mode (Full screen)
pub fn setKiosk(self: webui, status: bool) void {
    c.webui_set_kiosk(self.window_handle, status);
}

/// Check if a web browser is installed.
pub fn browserExist(browser: Browser) bool {
    return c.webui_browser_exist(browser);
}

/// Wait until all opened windows get closed.
/// This function should be **called** at the end, it will **block** the current thread
pub fn wait() void {
    c.webui_wait();
}

pub fn close(self: webui) void {
    c.webui_close(self.window_handle);
}

/// Close a specific window and free all memory resources.
pub fn destroy(self: webui) void {
    c.webui_destroy(self.window_handle);
}

/// Close all open windows.
/// `wait()` will return (Break)
pub fn exit() void {
    c.webui_exit();
}

/// Set the web-server root folder path for a specific window.
pub fn setRootFolder(self: webui, path: [:0]const u8) bool {
    return c.webui_set_root_folder(self.window_handle, path.ptr);
}

/// Set the web-server root folder path for all windows.
/// Should be used before `show()`.
pub fn setDefaultRootFolder(path: [:0]const u8) bool {
    return c.webui_set_default_root_folder(path.ptr);
}

/// Set a custom handler to serve files. This custom handler should
/// return full HTTP header and body.
/// This deactivates any previous handler set with `setFileHandlerWindow`.
pub fn setFileHandler(self: webui, comptime handler: fn (filename: []const u8) ?[]const u8) void {
    const tmp_struct = struct {
        fn handle(tmp_filename: [*:0]const u8, length: *c_int) callconv(.C) ?*const anyopaque {
            const len = std.mem.len(tmp_filename);
            const content = handler(tmp_filename[0..len]);
            if (content) |val| {
                length.* = @intCast(val.len);
                return @ptrCast(val.ptr);
            }

            return null;
        }
    };
    c.webui_set_file_handler(self.window_handle, tmp_struct.handle);
}

/// Set a custom handler to serve files. This custom handler should
/// return full HTTP header and body.
/// This deactivates any previous handler set with `setFileHandler`.
pub fn setFileHandlerWindow(self: webui, comptime handler: fn (window_handle: usize, filename: []const u8) ?[]const u8) void {
    const tmp_struct = struct {
        fn handle(window: usize, tmp_filename: [*:0]const u8, length: *c_int) callconv(.C) ?*const anyopaque {
            const len = std.mem.len(tmp_filename);
            const content = handler(window, tmp_filename[0..len]);
            if (content) |val| {
                length.* = @intCast(val.len);
                return @ptrCast(val.ptr);
            }

            return null;
        }
    };
    c.webui_set_file_handler_window(self.window_handle, tmp_struct.handle);
}

/// Check if the specified window is still running.
pub fn isShown(self: webui) bool {
    return c.webui_is_shown(self.window_handle);
}

/// Set the maximum time in seconds to wait for the window to connect
/// This effect `show()` and `wait()`. Value of `0` means wait forever.
pub fn setTimeout(time: usize) void {
    c.webui_set_timeout(time);
}

/// Set the default embedded HTML favicon.
pub fn setIcon(self: webui, icon: [:0]const u8, icon_type: [:0]const u8) void {
    c.webui_set_icon(self.window_handle, icon.ptr, icon_type);
}

/// Base64 encoding. Use this to safely send text based data to the UI. If
/// it fails it will return NULL.
pub fn encode(str: [:0]const u8) ?[]u8 {
    const ptr = c.webui_encode(str.ptr);
    if (ptr == null) {
        return null;
    }
    const len = std.mem.len(ptr);
    return ptr[0..len];
}

/// Base64 decoding.
/// Use this to safely decode received Base64 text from the UI.
/// If it fails it will return NULL.
pub fn decode(str: [:0]const u8) ?[]u8 {
    const ptr = c.webui_decode(str.ptr);
    if (ptr == null) {
        return null;
    }
    const len = std.mem.len(ptr);
    return ptr[0..len];
}

/// Safely free a buffer allocated by WebUI using
pub fn free(buf: []const u8) void {
    c.webui_free(@ptrCast(@constCast(buf.ptr)));
}

/// Safely allocate memory using the WebUI memory management system
/// it can be safely freed using `free()` at any time.
/// In general, you should not use this function
pub fn malloc(size: usize) []u8 {
    const ptr = c.webui_malloc(size).?; // TODO: Proper allocation failure check
    return @as([*]u8, @ptrCast(ptr))[0..size];
}

/// Safely send raw data to the UI. All clients.
pub fn sendRaw(self: webui, js_func: [:0]const u8, raw: []u8) void {
    c.webui_send_raw(self.window_handle, js_func.ptr, @ptrCast(raw.ptr), raw.len);
}

/// Set a window in hidden mode.
/// Should be called before `show()`
pub fn setHide(self: webui, status: bool) void {
    c.webui_set_hide(self.window_handle, status);
}

/// Set the window size.
pub fn setSize(self: webui, width: u32, height: u32) void {
    c.webui_set_size(self.window_handle, width, height);
}

/// Set the window minimum size.
pub fn setMinimumSize(self: webui, width: u32, height: u32) void {
    c.webui_set_minimum_size(self.window_handle, width, height);
}

/// Set the window position.
pub fn setPosition(self: webui, x: u32, y: u32) void {
    c.webui_set_position(self.window_handle, x, y);
}

/// Set the web browser profile to use.
/// An empty `name` and `path` means the default user profile.
/// Need to be called before `show()`.
pub fn setProfile(self: webui, name: [:0]const u8, path: [:0]const u8) void {
    c.webui_set_profile(self.window_handle, name.ptr, path.ptr);
}

/// Set the web browser proxy_server to use. Need to be called before `show()`
pub fn setProxy(self: webui, proxy_server: [:0]const u8) void {
    c.webui_set_proxy(self.window_handle, proxy_server.ptr);
}

/// Get the full current URL.
pub fn getUrl(self: webui) [:0]const u8 {
    const ptr = c.webui_get_url(self.window_handle);
    const len = std.mem.len(ptr);
    return ptr[0..len :0];
}

/// Open an URL in the native default web browser.
pub fn openUrl(url: [:0]const u8) void {
    c.webui_open_url(url.ptr);
}

/// Allow a specific window address to be accessible from a public network
pub fn setPublic(self: webui, status: bool) void {
    c.webui_set_public(self.window_handle, status);
}

/// Navigate to a specific URL. All clients.
pub fn navigate(self: webui, url: [:0]const u8) void {
    c.webui_navigate(self.window_handle, url.ptr);
}

/// Free all memory resources.
/// Should be called only at the end.
pub fn clean() void {
    c.webui_clean();
}

/// Delete all local web-browser profiles folder.
/// It should called at the end.
pub fn deleteAllProfiles() void {
    c.webui_delete_all_profiles();
}

/// Delete a specific window web-browser local folder profile.
pub fn deleteProfile(self: webui) void {
    c.webui_delete_profile(self.window_handle);
}

/// Get the ID of the parent process (The web browser may re-create another new process).
pub fn getParentProcessId(self: webui) usize {
    return c.webui_get_parent_process_id(self.window_handle);
}

/// Get the ID of the last child process.
pub fn getChildProcessId(self: webui) usize {
    return c.webui_get_child_process_id(self.window_handle);
}

/// Get the network port of a running window.
/// This can be useful to determine the HTTP link of `webui.js`
pub fn getPort(self: webui) usize {
    return c.webui_get_port(self.window_handle);
}

/// Set a custom web-server network port to be used by WebUI.
/// This can be useful to determine the HTTP link of `webui.js` in case
/// you are trying to use WebUI with an external web-server like NGNIX
/// Returns True if the port is free and usable by WebUI
pub fn setPort(self: webui, port: usize) bool {
    return c.webui_set_port(self.window_handle, port);
}

// Get an available usable free network port.
pub fn getFreePort() usize {
    return c.webui_get_free_port();
}

/// Control the WebUI behaviour. It's recommended to be called at the beginning.
pub fn setConfig(option: Config, status: bool) void {
    c.webui_set_config(option, status);
}

/// Control if UI events comming from this window should be processed
/// one a time in a single blocking thread `True`, or process every event in
/// a new non-blocking thread `False`. This update single window. You can use
/// `setConfig(ui_event_blocking, ...)` to update all windows.
pub fn setEventBlocking(self: webui, status: bool) void {
    c.webui_set_event_blocking(self.window_handle, status);
}

/// Get the HTTP mime type of a file.
pub fn getMimeType(file: [:0]const u8) [:0]const u8 {
    const res = c.webui_get_mime_type(file.ptr);
    return res[0..std.mem.len(res) :0];
}

/// Set the SSL/TLS certificate and the private key content,
/// both in PEM format.
/// This works only with `webui-2-secure` library.
/// If set empty WebUI will generate a self-signed certificate.
pub fn setTlsCertificate(certificate_pem: [:0]const u8, private_key_pem: [:0]const u8) bool {
    if (comptime !flags.enableTLS) {
        @panic("not enable tls");
    }
    return c.webui_set_tls_certificate(certificate_pem.ptr, private_key_pem.ptr);
}

/// Run JavaScript without waiting for the response.All clients.
pub fn run(self: webui, script_content: [:0]const u8) void {
    c.webui_run(self.window_handle, script_content.ptr);
}

/// Run JavaScript and get the response back. Work only in single client mode.
/// Make sure your local buffer can hold the response.
/// Return True if there is no execution error
pub fn script(self: webui, script_content: [:0]const u8, timeout: usize, buffer: []u8) bool {
    return c.webui_script(
        self.window_handle,
        script_content.ptr,
        timeout,
        buffer.ptr,
        buffer.len,
    );
}

/// Chose between Deno and Nodejs as runtime for .js and .ts files.
pub fn setRuntime(self: webui, runtime: Runtime) void {
    c.webui_set_runtime(self.window_handle, runtime);
}

/// Get how many arguments there are in an event
pub fn getCount(_: *Event) usize {
    @compileError("please use Event.getCount, this will be removed when zig-webui release");
}

/// Get an argument as integer at a specific index
pub fn getIntAt(_: *Event, _: usize) i64 {
    @compileError("please use Event.getIntAt, this will be removed when zig-webui release");
}

/// Get the first argument as integer
pub fn getInt(_: *Event) i64 {
    @compileError("please use Event.getInt, this will be removed when zig-webui release");
}

/// Get an argument as float at a specific index
pub fn getFloatAt(_: *Event, _: usize) f64 {
    @compileError("please use Event.getFloatAt, this will be removed when zig-webui release");
}

/// Get the first argument as float
pub fn getFloat(_: *Event) f64 {
    @compileError("please use Event.getFloat, this will be removed when zig-webui release");
}

/// Get an argument as string at a specific index
pub fn getStringAt(_: *Event, _: usize) [:0]const u8 {
    @compileError("please use Event.getStringAt, this will be removed when zig-webui release");
}

/// Get the first argument as string
pub fn getString(_: *Event) [:0]const u8 {
    @compileError("please use Event.getString, this will be removed when zig-webui release");
}

/// Get an argument as boolean at a specific index
pub fn getBoolAt(_: *Event, _: usize) bool {
    @compileError("please use Event.getBoolAt, this will be removed when zig-webui release");
}

/// Get the first argument as boolean
pub fn getBool(_: *Event) bool {
    @compileError("please use Event.getBool, this will be removed when zig-webui release");
}

/// Get the size in bytes of an argument at a specific index
pub fn getSizeAt(_: *Event, _: usize) usize {
    @compileError("please use Event.getSizeAt, this will be removed when zig-webui release");
}

/// Get size in bytes of the first argument
pub fn getSize(_: *Event) usize {
    @compileError("please use Event.getSize, this will be removed when zig-webui release");
}

/// **deprecated**: use Event.returnInt
/// Return the response to JavaScript as integer.
pub fn returnInt(_: *Event, _: i64) void {
    @compileError("please use Event.returnInt, this will be removed when zig-webui release");
}

/// **deprecated**: use Event.returnString
/// Return the response to JavaScript as string.
pub fn returnString(_: *Event, _: [:0]const u8) void {
    @compileError("please use Event.returnString, this will be removed when zig-webui release");
}

/// **deprecated**: use Event.returnBool
/// Return the response to JavaScript as boolean.
pub fn returnBool(_: *Event, _: bool) void {
    @compileError("please use Event.returnBool, this will be removed when zig-webui release");
}

/// Bind a specific HTML element click event with a function.
/// Empty element means all events.
pub fn interfaceBind(
    self: webui,
    element: [:0]const u8,
    comptime callback: fn (
        window_handle: usize,
        event_type: EventKind,
        element: []u8,
        event_number: usize,
        bind_id: usize,
    ) void,
) void {
    const tmp_struct = struct {
        fn handle(
            tmp_window: usize,
            tmp_event_type: EventKind,
            tmp_element: [*:0]u8,
            tmp_event_number: usize,
            tmp_bind_id: usize,
        ) callconv(.C) void {
            const len = std.mem.len(tmp_element);
            callback(tmp_window, tmp_event_type, tmp_element[0..len], tmp_event_number, tmp_bind_id);
        }
    };
    c.webui_interface_bind(self.window_handle, element.ptr, tmp_struct.handle);
}

/// When using `interfaceBind()`,
/// you may need this function to easily set a response.
pub fn interfaceSetResponse(self: webui, event_number: usize, response: [:0]const u8) void {
    c.webui_interface_set_response(self.window_handle, event_number, response.ptr);
}

/// Check if the app still running.
pub fn interfaceIsAppRunning() bool {
    return c.webui_interface_is_app_running();
}

/// Get a unique window ID.
pub fn interfaceGetWindowId(self: webui) usize {
    return c.webui_interface_get_window_id(self.window_handle);
}

/// Get an argument as string at a specific index
pub fn interfaceGetStringAt(self: webui, event_number: usize, index: usize) [:0]const u8 {
    const ptr = c.webui_interface_get_string_at(self.window_handle, event_number, index);
    const len = std.mem.len(ptr);
    return ptr[0..len :0];
}

/// Get an argument as integer at a specific index
pub fn interfaceGetIntAt(self: webui, event_number: usize, index: usize) i64 {
    return c.webui_interface_get_int_at(self.window_handle, event_number, index);
}

/// Get an argument as float at a specific index.
pub fn interfaceGetFloatAt(self: webui, event_number: usize, index: usize) f64 {
    return c.webui_interface_get_float_at(self.window_handle, event_number, index);
}

/// Get an argument as boolean at a specific index
pub fn interfaceGetBoolAt(self: webui, event_number: usize, index: usize) bool {
    return c.webui_interface_get_bool_at(self.window_handle, event_number, index);
}

/// Get the size in bytes of an argument at a specific index
pub fn interfaceGetSizeAt(self: webui, event_number: usize, index: usize) usize {
    return c.webui_interface_get_size_at(self.window_handle, event_number, index);
}

/// a very convenient function for binding callback.
/// you just need to pase a function to get param.
/// no need to care webui param api.
pub fn binding(self: webui, element: [:0]const u8, comptime callback: anytype) usize {
    const T = @TypeOf(callback);
    const TInfo = @typeInfo(T);

    if (TInfo != .Fn) {
        const err_msg = std.fmt.comptimePrint(
            "callback's type ({}), it must be a function!",
            .{T},
        );
        @compileError(err_msg);
    }

    const fnInfo = TInfo.Fn;
    if (fnInfo.return_type != void) {
        const err_msg = std.fmt.comptimePrint(
            "callback's return type ({}), it must be void!",
            .{fnInfo.return_type},
        );
        @compileError(err_msg);
    }

    if (fnInfo.is_generic) {
        const err_msg = std.fmt.comptimePrint(
            "callback's type ({}), it can not be a generic function!",
            .{T},
        );
        @compileError(err_msg);
    }

    if (fnInfo.is_var_args) {
        const err_msg = std.fmt.comptimePrint(
            "callback's type ({}), it can not have variable args!",
            .{T},
        );
        @compileError(err_msg);
    }

    const tmp_struct = struct {
        const tup_t = fnParamsToTuple(fnInfo.params);

        fn handle(e: *Event) void {
            var param_tup: tup_t = undefined;

            inline for (fnInfo.params, 0..fnInfo.params.len) |param, i| {
                if (param.type) |tt| {
                    const paramTInfo = @typeInfo(tt);
                    switch (paramTInfo) {
                        .Struct => {
                            if (tt != Event) {
                                const err_msg = std.fmt.comptimePrint(
                                    "the struct type is ({}), the struct type you can use only is Event in params!",
                                    .{tt},
                                );
                                @compileError(err_msg);
                            }
                            param_tup[i] = e;
                        },
                        .Bool => {
                            const res = getBoolAt(e, i);
                            param_tup[i] = res;
                        },
                        .Int => {
                            const res = getIntAt(e, i);
                            param_tup[i] = @intCast(res);
                        },
                        .Float => {
                            const res = getFloatAt(e, i);
                            param_tup[i] = res;
                        },
                        .Pointer => |pointer| {
                            if (pointer.size != .Slice or pointer.child != u8 or pointer.is_const == false) {
                                const err_msg = std.fmt.comptimePrint(
                                    "the pointer type is ({}), not support other type for pointer param!",
                                    .{tt},
                                );
                                @compileError(err_msg);
                            }
                            const str_ptr = getStringAt(e, i);
                            const tmp_str_len = getSizeAt(e, i);
                            const str: []const u8 = str_ptr[0..tmp_str_len];
                            param_tup[i] = str;
                        },
                        else => {
                            const err_msg = std.fmt.comptimePrint(
                                "type is ({}), only support these types: Event, Bool, Int, Float, []u8!",
                                .{tt},
                            );
                            @compileError(err_msg);
                        },
                    }
                } else {
                    @compileError("param must have type");
                }
            }

            @call(.auto, callback, param_tup);
        }
    };

    return self.bind(element, tmp_struct.handle);
}

/// this funciton will return a fn's params tuple
fn fnParamsToTuple(comptime params: []const std.builtin.Type.Fn.Param) type {
    const Type = std.builtin.Type;
    const fields: [params.len]Type.StructField = blk: {
        var res: [params.len]Type.StructField = undefined;

        for (params, 0..params.len) |param, i| {
            res[i] = Type.StructField{
                .type = param.type.?,
                .alignment = @alignOf(param.type.?),
                .default_value = null,
                .is_comptime = false,
                .name = std.fmt.comptimePrint("{}", .{i}),
            };
        }
        break :blk res;
    };
    return @Type(.{
        .Struct = std.builtin.Type.Struct{
            .layout = .Auto,
            .is_tuple = true,
            .decls = &.{},
            .fields = &fields,
        },
    });
}

pub const WEBUI_VERSION: std.SemanticVersion = .{
    .major = 2,
    .minor = 5,
    .patch = 0,
    .pre = "beta.2",
};

/// Max windows, servers and threads
pub const WEBUI_MAX_IDS = 256;

/// Max allowed argument's index
pub const WEBUI_MAX_ARG = 16;

pub const Browser = enum(usize) {
    /// 0. No web browser
    NoBrowser = 0,
    /// 1. Default recommended web browser
    AnyBrowser,
    /// 2. Google Chrome
    Chrome,
    /// 3. Mozilla Firefox
    Firefox,
    /// 4. Microsoft Edge
    Edge,
    /// 5. Apple Safari
    Safari,
    /// 6. The Chromium Project
    Chromium,
    /// 7. Opera Browser
    Opera,
    /// 8. The Brave Browser
    Brave,
    /// 9. The Vivaldi Browser
    Vivaldi,
    /// 10. The Epic Browser
    Epic,
    /// 11. The Yandex Browser
    Yandex,
    /// 12. Any Chromium based browser
    ChromiumBased,
    /// 13. WebView (Non-web-browser)
    Webview,
};

pub const Runtime = enum(usize) {
    /// 0. Prevent WebUI from using any runtime for .js and .ts files
    None = 0,
    /// 1. Use Deno runtime for .js and .ts files
    Deno,
    /// 2. Use Nodejs runtime for .js files
    NodeJS,
    /// 3. Use Bun runtime for .js and .ts files
    Bun,
};

pub const EventKind = enum(usize) {
    /// 0. Window disconnection event
    EVENT_DISCONNECTED = 0,
    /// 1. Window connection event
    EVENT_CONNECTED,
    /// 2. Mouse click event
    EVENT_MOUSE_CLICK,
    /// 3. Window navigation event
    EVENT_NAVIGATION,
    /// 4. Function call event
    EVENT_CALLBACK,
};

pub const Config = enum(c_int) {
    /// Control if `show()`,`c.webui_show_browser`,`c.webui_show_wv` should wait
    /// for the window to connect before returns or not.
    /// Default: True
    show_wait_connection = 0,
    /// Control if WebUI should block and process the UI events
    /// one a time in a single thread `True`, or process every
    /// event in a new non-blocking thread `False`. This updates
    /// all windows. You can use `setEventBlocking()` for
    /// a specific single window update.
    /// Default: False
    ui_event_blocking = 1,
    /// Automatically refresh the window UI when any file in the
    /// root folder gets changed.
    /// Default: False
    folder_monitor,
    /// Allow multiple clients to connect to the same window,
    /// This is helpful for web apps (non-desktop software),
    /// Please see the documentation for more details.
    /// Default: False
    multi_client,
    /// Allow multiple clients to connect to the same window,
    /// This is helpful for web apps (non-desktop software),
    /// Please see the documentation for more details.
    /// Default: False
    use_cookies,
};

pub const Event = extern struct {
    /// The window object number
    window: usize,
    /// Event type
    event_type: EventKind,
    /// HTML element ID
    element: [*:0]u8,
    /// Internal WebUI
    event_number: usize,
    /// Bind ID
    bind_id: usize,
    /// Client's unique ID
    client_id: usize,
    /// Client's connection ID
    connection_id: usize,
    /// Client's full cookies
    cookies: [*:0]u8,

    /// get window through Event
    pub fn getWindow(self: Event) webui {
        return .{
            .window_handle = self.window,
        };
    }

    /// Show a window using embedded HTML, or a file.
    /// If the window is already open, it will be refreshed. Single client.
    pub fn showClient(self: *Event, content: [:0]const u8) bool {
        return c.webui_show_client(self, content.ptr);
    }

    /// Close a specific client.
    pub fn closeClient(self: *Event) void {
        c.webui_close_client(self);
    }

    /// Safely send raw data to the UI. Single client.
    pub fn sendRawClient(self: *Event, function: [:0]const u8, buffer: []const u8) void {
        c.webui_send_raw_client(
            self,
            function.ptr,
            @ptrCast(buffer.ptr),
            buffer.len,
        );
    }

    /// Navigate to a specific URL. Single client.
    pub fn navigateClient(self: *Event, url: [:0]const u8) void {
        c.webui_navigate_client(self, url.ptr);
    }

    /// Run JavaScript without waiting for the response. Single client.
    pub fn runClient(self: *Event, script_content: [:0]const u8) void {
        c.webui_run_client(self, script_content.ptr);
    }

    /// Run JavaScript and get the response back. Single client.
    /// Make sure your local buffer can hold the response.
    pub fn scriptClient(
        self: *Event,
        script_content: [:0]const u8,
        timeout: usize,
        buffer: []u8,
    ) bool {
        return c.webui_script_client(
            self,
            script_content.ptr,
            timeout,
            buffer.ptr,
            buffer.len,
        );
    }

    /// Return the response to JavaScript as integer.
    pub fn returnInt(e: *Event, n: i64) void {
        c.webui_return_int(e, n);
    }

    /// Return the response to JavaScript as float.
    pub fn returnFloat(e: *Event, f: f64) void {
        c.webui_return_float(e, f);
    }

    /// Return the response to JavaScript as string.
    pub fn returnString(e: *Event, str: [:0]const u8) void {
        c.webui_return_string(e, str.ptr);
    }

    /// Return the response to JavaScript as boolean.
    pub fn returnBool(e: *Event, b: bool) void {
        c.webui_return_bool(e, b);
    }

    /// a convenient function to return value
    /// no need to care about the function name, you just need to call returnValue
    pub fn returnValue(e: *Event, val: anytype) void {
        const T = @TypeOf(val);
        const type_info = @typeInfo(T);

        const is_dev = builtin.zig_version.minor > 13;

        switch (type_info) {
            if (is_dev) .pointer else .Pointer => |pointer| {
                if (pointer.size == .Slice and
                    pointer.child == u8 and
                    (if (pointer.sentinel) |sentinel| @as(*u8, @ptrCast(sentinel)).* == 0 else false))
                {
                    e.returnString(val);
                } else {
                    const err_msg = std.fmt.comptimePrint("val's type ({}), only support []const u8 for Pointer!", .{T});
                    @compileError(err_msg);
                }
            },
            if (is_dev) .int else .Int => |int| {
                const bits = int.bits;
                const is_signed = int.signedness == .signed;
                if (is_signed and bits <= 64) {
                    e.returnInt(@intCast(val));
                } else if (!is_signed and bits <= 63) {
                    e.returnInt(@intCast(val));
                } else {
                    const err_msg = std.fmt.comptimePrint("val's type ({}), out of i64", .{T});
                    @compileError(err_msg);
                }
            },
            if (is_dev) .bool else .Bool => e.returnBool(val),
            if (is_dev) .float else .Float => e.returnFloat(val),
            else => {
                const err_msg = std.fmt.comptimePrint("val's type ({}), only support int, bool, string([]const u8)!", .{T});
                @compileError(err_msg);
            },
        }
    }

    /// Get how many arguments there are in an event
    pub fn getCount(e: *Event) usize {
        return c.webui_get_count(e);
    }

    /// Get an argument as integer at a specific index
    pub fn getIntAt(e: *Event, index: usize) i64 {
        return c.webui_get_int_at(e, index);
    }

    /// Get the first argument as integer
    pub fn getInt(e: *Event) i64 {
        return c.webui_get_int(e);
    }

    /// Get an argument as float at a specific index
    pub fn getFloatAt(e: *Event, index: usize) f64 {
        return c.webui_get_float_at(e, index);
    }

    /// Get the first argument as float
    pub fn getFloat(e: *Event) f64 {
        c.webui_get_float(e);
    }

    /// Get an argument as string at a specific index
    pub fn getStringAt(e: *Event, index: usize) [:0]const u8 {
        const ptr = c.webui_get_string_at(e, index);
        const len = std.mem.len(ptr);
        return ptr[0..len :0];
    }

    /// Get the first argument as string
    pub fn getString(e: *Event) [:0]const u8 {
        const ptr = c.webui_get_string(e);
        const len = std.mem.len(ptr);
        return ptr[0..len :0];
    }

    /// Get an argument as boolean at a specific index
    pub fn getBoolAt(e: *Event, index: usize) bool {
        return c.webui_get_bool_at(e, index);
    }

    /// Get the first argument as boolean
    pub fn getBool(e: *Event) bool {
        return c.webui_get_bool(e);
    }

    /// Get the size in bytes of an argument at a specific index
    pub fn getSizeAt(e: *Event, index: usize) usize {
        return c.webui_get_size_at(e, index);
    }

    /// Get size in bytes of the first argument
    pub fn getSize(e: *Event) usize {
        return c.webui_get_size(e);
    }
};
