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

/// The window number. Do not modify.
window_handle: usize,

/// Creating a new WebUI window object.
pub fn newWindow() webui {
    return .{
        .window_handle = webui_new_window(),
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
        .window_handle = webui_new_window_id(id),
    };
}

/// Get a free window number that can be used with
/// `newWindowWithId`
pub fn getNewWindowId() usize {
    return webui_get_new_window_id();
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
    return webui_bind(self.window_handle, element.ptr, tmp_struct.handle);
}

/// Get the recommended web browser ID to use. If you
/// are already using one, this function will return the same ID.
pub fn getBestBrowser(self: webui) Browser {
    return webui_get_best_browser(self.window_handle);
}

/// Show a window using embedded HTML, or a file.
/// If the window is already open, it will be refreshed.
/// This will refresh all windows in multi-client mode.
/// Returns True if showing the window is successed
/// `content` is the html which will be shown
pub fn show(self: webui, content: [:0]const u8) bool {
    return webui_show(self.window_handle, content.ptr);
}

/// Same as `show()`. But using a specific web browser
/// Returns True if showing the window is successed
pub fn showBrowser(self: webui, content: [:0]const u8, browser: Browser) bool {
    return webui_show_browser(self.window_handle, content.ptr, browser);
}

/// Same as `show()`. But start only the web server and return the URL.
/// No window will be shown.
pub fn startServer(self: webui, path: [:0]const u8) [:0]const u8 {
    const url = webui_start_server(self.window_handle, path.ptr);
    const url_len = std.mem.len(url);
    return url[0..url_len :0];
}

/// Show a WebView window using embedded HTML, or a file. If the window is already
/// opend, it will be refreshed. Note: Win32 need `WebView2Loader.dll`.
/// Returns True if if showing the WebView window is successed.
pub fn showWv(self: webui, content: [:0]const u8) bool {
    return webui_show_wv(self.window_handle, content.ptr);
}

/// Set the window in Kiosk mode (Full screen)
pub fn setKiosk(self: webui, status: bool) void {
    webui_set_kiosk(self.window_handle, status);
}

/// Check if a web browser is installed.
pub fn browserExist(browser: Browser) bool {
    return webui_browser_exist(browser);
}

/// Wait until all opened windows get closed.
/// This function should be **called** at the end, it will **block** the current thread
pub fn wait() void {
    webui_wait();
}

pub fn close(self: webui) void {
    webui_close(self.window_handle);
}

/// Close a specific window and free all memory resources.
pub fn destroy(self: webui) void {
    webui_destroy(self.window_handle);
}

/// Close all open windows.
/// `wait()` will return (Break)
pub fn exit() void {
    webui_exit();
}

/// Set the web-server root folder path for a specific window.
pub fn setRootFolder(self: webui, path: [:0]const u8) bool {
    return webui_set_root_folder(self.window_handle, path.ptr);
}

/// Set the web-server root folder path for all windows.
/// Should be used before `show()`.
pub fn setDefaultRootFolder(path: [:0]const u8) bool {
    return webui_set_default_root_folder(path.ptr);
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
    webui_set_file_handler(self.window_handle, tmp_struct.handle);
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
    webui_set_file_handler_window(self.window_handle, tmp_struct.handle);
}

/// Check if the specified window is still running.
pub fn isShown(self: webui) bool {
    return webui_is_shown(self.window_handle);
}

/// Set the maximum time in seconds to wait for the window to connect
/// This effect `show()` and `wait()`. Value of `0` means wait forever.
pub fn setTimeout(time: usize) void {
    webui_set_timeout(time);
}

/// Set the default embedded HTML favicon.
pub fn setIcon(self: webui, icon: [:0]const u8, icon_type: [:0]const u8) void {
    webui_set_icon(self.window_handle, icon.ptr, icon_type);
}

/// Base64 encoding. Use this to safely send text based data to the UI. If
/// it fails it will return NULL.
pub fn encode(str: [:0]const u8) ?[]u8 {
    const ptr = webui_encode(str.ptr);
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
    const ptr = webui_decode(str.ptr);
    if (ptr == null) {
        return null;
    }
    const len = std.mem.len(ptr);
    return ptr[0..len];
}

/// Safely free a buffer allocated by WebUI using
pub fn free(buf: []const u8) void {
    webui_free(@ptrCast(@constCast(buf.ptr)));
}

/// Safely allocate memory using the WebUI memory management system
/// it can be safely freed using `free()` at any time.
/// In general, you should not use this function
pub fn malloc(size: usize) []u8 {
    const ptr = webui_malloc(size).?; // TODO: Proper allocation failure check
    return @as([*]u8, @ptrCast(ptr))[0..size];
}

/// Safely send raw data to the UI. All clients.
pub fn sendRaw(self: webui, js_func: [:0]const u8, raw: []u8) void {
    webui_send_raw(self.window_handle, js_func.ptr, @ptrCast(raw.ptr), raw.len);
}

/// Set a window in hidden mode.
/// Should be called before `show()`
pub fn setHide(self: webui, status: bool) void {
    webui_set_hide(self.window_handle, status);
}

/// Set the window size.
pub fn setSize(self: webui, width: u32, height: u32) void {
    webui_set_size(self.window_handle, width, height);
}

/// Set the window minimum size.
pub fn setMinimumSize(self: webui, width: u32, height: u32) void {
    webui_set_minimum_size(self.window_handle, width, height);
}

/// Set the window position.
pub fn setPosition(self: webui, x: u32, y: u32) void {
    webui_set_position(self.window_handle, x, y);
}

/// Set the web browser profile to use.
/// An empty `name` and `path` means the default user profile.
/// Need to be called before `show()`.
pub fn setProfile(self: webui, name: [:0]const u8, path: [:0]const u8) void {
    webui_set_profile(self.window_handle, name.ptr, path.ptr);
}

/// Set the web browser proxy_server to use. Need to be called before `show()`
pub fn setProxy(self: webui, proxy_server: [:0]const u8) void {
    webui_set_proxy(self.window_handle, proxy_server.ptr);
}

/// Get the full current URL.
pub fn getUrl(self: webui) [:0]const u8 {
    const ptr = webui_get_url(self.window_handle);
    const len = std.mem.len(ptr);
    return ptr[0..len :0];
}

/// Open an URL in the native default web browser.
pub fn openUrl(url: [:0]const u8) void {
    webui_open_url(url.ptr);
}

/// Allow a specific window address to be accessible from a public network
pub fn setPublic(self: webui, status: bool) void {
    webui_set_public(self.window_handle, status);
}

/// Navigate to a specific URL. All clients.
pub fn navigate(self: webui, url: [:0]const u8) void {
    webui_navigate(self.window_handle, url.ptr);
}

/// Free all memory resources.
/// Should be called only at the end.
pub fn clean() void {
    webui_clean();
}

/// Delete all local web-browser profiles folder.
/// It should called at the end.
pub fn deleteAllProfiles() void {
    webui_delete_all_profiles();
}

/// Delete a specific window web-browser local folder profile.
pub fn deleteProfile(self: webui) void {
    webui_delete_profile(self.window_handle);
}

/// Get the ID of the parent process (The web browser may re-create another new process).
pub fn getParentProcessId(self: webui) usize {
    return webui_get_parent_process_id(self.window_handle);
}

/// Get the ID of the last child process.
pub fn getChildProcessId(self: webui) usize {
    return webui_get_child_process_id(self.window_handle);
}

/// Get the network port of a running window.
/// This can be useful to determine the HTTP link of `webui.js`
pub fn getPort(self: webui) usize {
    return webui_get_port(self.window_handle);
}

/// Set a custom web-server network port to be used by WebUI.
/// This can be useful to determine the HTTP link of `webui.js` in case
/// you are trying to use WebUI with an external web-server like NGNIX
/// Returns True if the port is free and usable by WebUI
pub fn setPort(self: webui, port: usize) bool {
    return webui_set_port(self.window_handle, port);
}

// Get an available usable free network port.
pub fn getFreePort() usize {
    return webui_get_free_port();
}

/// Control the WebUI behaviour. It's recommended to be called at the beginning.
pub fn setConfig(option: Config, status: bool) void {
    webui_set_config(option, status);
}

/// Control if UI events comming from this window should be processed
/// one a time in a single blocking thread `True`, or process every event in
/// a new non-blocking thread `False`. This update single window. You can use
/// `setConfig(ui_event_blocking, ...)` to update all windows.
pub fn setEventBlocking(self: webui, status: bool) void {
    webui_set_event_blocking(self.window_handle, status);
}

/// Get the HTTP mime type of a file.
pub fn getMimeType(file: [:0]const u8) [:0]const u8 {
    const res = webui_get_mime_type(file.ptr);
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
    return webui_set_tls_certificate(certificate_pem.ptr, private_key_pem.ptr);
}

/// Run JavaScript without waiting for the response.All clients.
pub fn run(self: webui, script_content: [:0]const u8) void {
    webui_run(self.window_handle, script_content.ptr);
}

/// Run JavaScript and get the response back. Work only in single client mode.
/// Make sure your local buffer can hold the response.
/// Return True if there is no execution error
pub fn script(self: webui, script_content: [:0]const u8, timeout: usize, buffer: []u8) bool {
    return webui_script(
        self.window_handle,
        script_content.ptr,
        timeout,
        buffer.ptr,
        buffer.len,
    );
}

/// Chose between Deno and Nodejs as runtime for .js and .ts files.
pub fn setRuntime(self: webui, runtime: Runtime) void {
    webui_set_runtime(self.window_handle, runtime);
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
    webui_interface_bind(self.window_handle, element.ptr, tmp_struct.handle);
}

/// When using `interfaceBind()`,
/// you may need this function to easily set a response.
pub fn interfaceSetResponse(self: webui, event_number: usize, response: [:0]const u8) void {
    webui_interface_set_response(self.window_handle, event_number, response.ptr);
}

/// Check if the app still running.
pub fn interfaceIsAppRunning() bool {
    return webui_interface_is_app_running();
}

/// Get a unique window ID.
pub fn interfaceGetWindowId(self: webui) usize {
    return webui_interface_get_window_id(self.window_handle);
}

/// Get an argument as string at a specific index
pub fn interfaceGetStringAt(self: webui, event_number: usize, index: usize) [:0]const u8 {
    const ptr = webui_interface_get_string_at(self.window_handle, event_number, index);
    const len = std.mem.len(ptr);
    return ptr[0..len :0];
}

/// Get an argument as integer at a specific index
pub fn interfaceGetIntAt(self: webui, event_number: usize, index: usize) i64 {
    return webui_interface_get_int_at(self.window_handle, event_number, index);
}

/// Get an argument as float at a specific index.
pub fn interfaceGetFloatAt(self: webui, event_number: usize, index: usize) f64 {
    return webui_interface_get_float_at(self.window_handle, event_number, index);
}

/// Get an argument as boolean at a specific index
pub fn interfaceGetBoolAt(self: webui, event_number: usize, index: usize) bool {
    return webui_interface_get_bool_at(self.window_handle, event_number, index);
}

/// Get the size in bytes of an argument at a specific index
pub fn interfaceGetSizeAt(self: webui, event_number: usize, index: usize) usize {
    return webui_interface_get_size_at(self.window_handle, event_number, index);
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
    /// Control if `show()`,`webui_show_browser`,`webui_show_wv` should wait
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
        return webui_show_client(self, content.ptr);
    }

    /// Close a specific client.
    pub fn closeClient(self: *Event) void {
        webui_close_client(self);
    }

    /// Safely send raw data to the UI. Single client.
    pub fn sendRawClient(self: *Event, function: [:0]const u8, buffer: []const u8) void {
        webui_send_raw_client(
            self,
            function.ptr,
            @ptrCast(buffer.ptr),
            buffer.len,
        );
    }

    /// Navigate to a specific URL. Single client.
    pub fn navigateClient(self: *Event, url: [:0]const u8) void {
        webui_navigate_client(self, url.ptr);
    }

    /// Run JavaScript without waiting for the response. Single client.
    pub fn runClient(self: *Event, script_content: [:0]const u8) void {
        webui_run_client(self, script_content.ptr);
    }

    /// Run JavaScript and get the response back. Single client.
    /// Make sure your local buffer can hold the response.
    pub fn scriptClient(
        self: *Event,
        script_content: [:0]const u8,
        timeout: usize,
        buffer: []u8,
    ) bool {
        return webui_script_client(
            self,
            script_content.ptr,
            timeout,
            buffer.ptr,
            buffer.len,
        );
    }

    /// Return the response to JavaScript as integer.
    pub fn returnInt(e: *Event, n: i64) void {
        webui_return_int(e, n);
    }

    /// Return the response to JavaScript as float.
    pub fn returnFloat(e: *Event, f: f64) void {
        webui_return_float(e, f);
    }

    /// Return the response to JavaScript as string.
    pub fn returnString(e: *Event, str: [:0]const u8) void {
        webui_return_string(e, str.ptr);
    }

    /// Return the response to JavaScript as boolean.
    pub fn returnBool(e: *Event, b: bool) void {
        webui_return_bool(e, b);
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
        return webui_get_count(e);
    }

    /// Get an argument as integer at a specific index
    pub fn getIntAt(e: *Event, index: usize) i64 {
        return webui_get_int_at(e, index);
    }

    /// Get the first argument as integer
    pub fn getInt(e: *Event) i64 {
        return webui_get_int(e);
    }

    /// Get an argument as float at a specific index
    pub fn getFloatAt(e: *Event, index: usize) f64 {
        return webui_get_float_at(e, index);
    }

    /// Get the first argument as float
    pub fn getFloat(e: *Event) f64 {
        webui_get_float(e);
    }

    /// Get an argument as string at a specific index
    pub fn getStringAt(e: *Event, index: usize) [:0]const u8 {
        const ptr = webui_get_string_at(e, index);
        const len = std.mem.len(ptr);
        return ptr[0..len :0];
    }

    /// Get the first argument as string
    pub fn getString(e: *Event) [:0]const u8 {
        const ptr = webui_get_string(e);
        const len = std.mem.len(ptr);
        return ptr[0..len :0];
    }

    /// Get an argument as boolean at a specific index
    pub fn getBoolAt(e: *Event, index: usize) bool {
        return webui_get_bool_at(e, index);
    }

    /// Get the first argument as boolean
    pub fn getBool(e: *Event) bool {
        return webui_get_bool(e);
    }

    /// Get the size in bytes of an argument at a specific index
    pub fn getSizeAt(e: *Event, index: usize) usize {
        return webui_get_size_at(e, index);
    }

    /// Get size in bytes of the first argument
    pub fn getSize(e: *Event) usize {
        return webui_get_size(e);
    }
};

/// @brief Create a new WebUI window object.
///
/// @return Returns the window number.
///
/// @example const my_window: usize = webui_new_window();
pub extern fn webui_new_window() callconv(.C) usize;

/// @brief Create a new webui window object using a specified window number.
///
/// @param window_number The window number (should be > 0, and < WEBUI_MAX_IDS)
///
/// @return Returns the same window number if success.
///
/// @example const my_window: usize = webui_new_window_id(123);
pub extern fn webui_new_window_id(window_number: usize) callconv(.C) usize;

/// @brief Get a free window number that can be used with `webui_new_window_id()`
///
/// @return Returns the first available free window number. Starting from 1.
///
/// @example const my_window: usize = webui_get_new_window_id();
pub extern fn webui_get_new_window_id() callconv(.C) usize;

/// @brief Bind an HTML element and a Javascript object with a backend function. Empty
/// element name means all events.
///
/// @param window The window number
/// @param element The HTML element / Javascript object
/// @param func The callback function
///
/// @return Returns a unique bind ID.
///
/// @example webui_bind(my_window, "myFunction", myFunction);
pub extern fn webui_bind(
    window: usize,
    element: [*:0]const u8,
    func: *const fn (e: *Event) callconv(.C) void,
) callconv(.C) usize;

/// @brief Get the recommended web browser ID to use. If you
/// are already using one, this function will return the same ID.
///
/// @param The window number
///
/// @return Returns a web browser ID.
///
/// @example const browser_id: usize = webui_get_best_browser(my_window);
pub extern fn webui_get_best_browser(window: usize) callconv(.C) Browser;

/// @brief Show a window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. This will refresh all windows in multi-client mode.
///
/// @param window The window number
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show(my_window, "<html>...</html>"); |
/// webui_show(my_window, "index.html"); | webui_show(my_window, "http://...");
pub extern fn webui_show(window: usize, content: [*:0]const u8) callconv(.C) bool;

/// @brief Show a window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. Single client.
///
/// @param e The event struct
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show_client(e, "<html>...</html>"); |
/// webui_show_client(e, "index.html"); | webui_show_client(e, "http://...");
pub extern fn webui_show_client(e: *Event, content: [*:0]const u8) callconv(.C) bool;

/// @brief Same as `webui_show()`. But using a specific web browser.
///
/// @param window The window number
/// @param content The HTML, URL, Or a local file
/// @param browser The web browser to be used
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show_browser(my_window, "<html>...</html>", .Chrome); |
/// webui_show_browser(my_window, "index.html", .Firefox);
pub extern fn webui_show_browser(
    window: usize,
    content: [*:0]const u8,
    browser: Browser,
) callconv(.C) bool;

/// @brief Same as `webui_show()`. But start only the web server and return the URL.
/// No window will be shown.
///
/// @param window The window number
/// @param content The HTML, Or a local file
///
/// @return Returns the url of this window server.
///
/// @example const url: [*:0]const u8 = webui_start_server(my_window, "/full/root/path");
pub extern fn webui_start_server(
    window: usize,
    content: [*:0]const u8,
) callconv(.C) [*:0]const u8;

/// @brief Show a WebView window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. Note: Win32 need `WebView2Loader.dll`.
///
/// @param window The window number
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the WebView window is successed.
///
/// @example webui_show_wv(my_window, "<html>...</html>"); | webui_show_wv(my_window,
/// "index.html"); | webui_show_wv(my_window, "http://...");
pub extern fn webui_show_wv(window: usize, content: [*:0]const u8) callconv(.C) bool;

/// @brief Set the window in Kiosk mode (Full screen).
///
/// @param window The window number
/// @param status True or False
///
/// @example webui_set_kiosk(my_window, true);
pub extern fn webui_set_kiosk(window: usize, status: bool) callconv(.C) void;

/// @brief Set the window with high-contrast support. Useful when you want to
/// build a better high-contrast theme with CSS.
///
/// @param window The window number
/// @param status True or False
///
/// @example webui_set_high_contrast(my_window, true);
pub extern fn webui_set_high_contrast(window: usize, status: bool) callconv(.C) void;

/// @brief Get OS high contrast preference.
///
/// @return Returns True if OS is using high contrast theme
///
/// @example const hc: bool = webui_is_high_contrast();
pub extern fn webui_is_high_contrast() callconv(.C) bool;

/// @brief Check if a web browser is installed.
///
/// @return Returns True if the specified browser is available.
///
/// @example const status: bool = webui_browser_exist(.Chrome);
pub extern fn webui_browser_exist(browser: Browser) callconv(.C) bool;

/// @brief Wait until all opened windows get closed.
///
/// @example webui_wait();
pub extern fn webui_wait() callconv(.C) void;

/// @brief Close a specific window only. The window object will still exist.
/// All clients.
///
/// @param The window number
///
/// @example webui_close(my_window);
pub extern fn webui_close(window: usize) callconv(.C) void;

/// @brief Close a specific client.
///
/// @param e The event struct
///
/// @example webui_close_client(e);
pub extern fn webui_close_client(e: *Event) callconv(.C) void;

/// @brief Close a specific window and free all memory resources.
///
/// @param window The window number
///
/// @example webui_destroy(my_window);
pub extern fn webui_destroy(window: usize) callconv(.C) void;

/// @brief Close all open windows. `webui_wait()` will return (Break).
///
/// @example webui_exit();
pub extern fn webui_exit() callconv(.C) void;

/// @brief Set the web-server root folder path for a specific window.
///
/// @param window The window number
/// @param path The local folder full path
///
/// @example webui_set_root_folder(my_window, "/home/Foo/Bar/");
pub extern fn webui_set_root_folder(window: usize, path: [*:0]const u8) callconv(.C) bool;

/// @brief Set the web-server root folder path for all windows. Should be used
/// before `webui_show()`.
///
/// @param path The local folder full path
///
/// @example webui_set_default_root_folder("/home/Foo/Bar/");
pub extern fn webui_set_default_root_folder(path: [*:0]const u8) callconv(.C) bool;

/// @brief Set a custom handler to serve files. This custom handler should
/// return full HTTP header and body.
/// This deactivates any previous handler set with `webui_set_file_handler_window`
///
/// @param window The window number
/// @param handler The handler function: `void myHandler(filename: [*:0]const u8,
/// length: *c_int)`
///
/// @example webui_set_file_handler(my_window, myHandlerFunction);
pub extern fn webui_set_file_handler(
    window: usize,
    handler: *const fn (filename: [*:0]const u8, length: *c_int) callconv(.C) ?*const anyopaque,
) callconv(.C) void;

/// @brief Set a custom handler to serve files. This custom handler should
/// return full HTTP header and body.
/// This deactivates any previous handler set with `webui_set_file_handler`
///
/// @param window The window number
/// @param handler The handler function: `void myHandler(window: usize, filename: [*:0]const u8,
/// length: *c_int)`
///
/// @example webui_set_file_handler_window(my_window, myHandlerFunction);
pub extern fn webui_set_file_handler_window(
    window: usize,
    handler: *const fn (
        window: usize,
        filename: [*:0]const u8,
        length: *c_int,
    ) callconv(.C) ?*const anyopaque,
) callconv(.C) void;

/// @brief Check if the specified window is still running.
///
/// @param window The window number
///
/// @example webui_is_shown(my_window);
pub extern fn webui_is_shown(window: usize) callconv(.C) bool;

/// @brief Set the maximum time in seconds to wait for the window to connect.
/// This effect `show()` and `wait()`. Value of `0` means wait forever.
///
/// @param second The timeout in seconds
///
/// @example webui_set_timeout(30);
pub extern fn webui_set_timeout(second: usize) callconv(.C) void;

/// @brief Set the default embedded HTML favicon.
///
/// @param window The window number
/// @param icon The icon as string: `<svg>...</svg>`
/// @param icon_type The icon type: `image/svg+xml`
///
/// @example webui_set_icon(my_window, "<svg>...</svg>", "image/svg+xml");
pub extern fn webui_set_icon(
    window: usize,
    icon: [*:0]const u8,
    icon_type: [*:0]const u8,
) callconv(.C) void;

/// @brief Encode text to Base64. The returned buffer need to be freed.
///
/// @param str The string to encode (Should be null terminated)
///
/// @return Returns the base64 encoded string
///
/// @example const base64: [*:0]u8 = webui_encode("Foo Bar");
pub extern fn webui_encode(str: [*:0]const u8) callconv(.C) ?[*:0]u8;

/// @brief Decode a Base64 encoded text. The returned buffer need to be freed.
///
/// @param str The string to decode (Should be null terminated)
///
/// @return Returns the base64 decoded string
///
/// @example const str: [*:0]u8 = webui_decode("SGVsbG8=");
pub extern fn webui_decode(str: [*:0]const u8) callconv(.C) ?[*:0]u8;

/// @brief Safely free a buffer allocated by WebUI using `webui_malloc()`.
///
/// @param ptr The buffer to be freed
///
/// @example webui_free(my_buffer);
pub extern fn webui_free(ptr: *anyopaque) callconv(.C) void;

/// @brief Safely allocate memory using the WebUI memory management system. It
/// can be safely freed using `webui_free()` at any time.
///
/// @param size The size of memory in bytes
///
/// @example var my_buffer: [*:0]u8 = @ptrCast(@alignCast(webui_malloc(1024)));
pub extern fn webui_malloc(size: usize) callconv(.C) ?*anyopaque;

/// @brief Safely send raw data to the UI. All clients.
///
/// @param window The window number
/// @param function The JavaScript function to receive raw data: `function
/// myFunc(my_data){}`
/// @param raw The raw data buffer
/// @param size The raw data size in bytes
///
/// @example webui_send_raw(my_window, "myJavaScriptFunc", my_buffer, 64);
pub extern fn webui_send_raw(
    window: usize,
    function: [*:0]const u8,
    raw: [*]const anyopaque,
    size: usize,
) callconv(.C) void;

/// @brief Safely send raw data to the UI. Single client.
///
/// @param e The event struct
/// @param function The JavaScript function to receive raw data: `function
/// myFunc(my_data){}`
/// @param raw The raw data buffer
/// @param size The raw data size in bytes
///
/// @example webui_send_raw_client(e, "myJavaScriptFunc", my_buffer, 64);
pub extern fn webui_send_raw_client(
    e: *Event,
    function: [*:0]const u8,
    raw: [*]const anyopaque,
    size: usize,
) callconv(.C) void;

/// @brief Set a window in hidden mode. Should be called before `webui_show()`.
///
/// @param window The window number
/// @param status The status: True or False
///
/// @example webui_set_hide(my_window, true);
pub extern fn webui_set_hide(window: usize, status: bool) callconv(.C) void;

/// @brief Set the window size.
///
/// @param window The window number
/// @param width The window width
/// @param height The window height
///
/// @example webui_set_size(my_window, 800, 600);
pub extern fn webui_set_size(window: usize, width: u32, height: u32) callconv(.C) void;

/// @brief Set the window minimum size.
///
/// @param window The window number
/// @param width The window width
/// @param height The window height
///
/// @example webui_set_minimum_size(my_window, 800, 600);
pub extern fn webui_set_minimum_size(
    window: usize,
    width: u32,
    height: u32,
) callconv(.C) void;

/// @brief Set the window position.
///
/// @param window The window number
/// @param x The window X
/// @param y The window Y
///
/// @example webui_set_position(my_window, 100, 100);
pub extern fn webui_set_position(window: usize, x: u32, y: u32) callconv(.C) void;

/// @brief Set the web browser profile to use. An empty `name` and `path` means
/// the default user profile. Need to be called before `webui_show()`.
///
/// @param window The window number
/// @param name The web browser profile name
/// @param path The web browser profile full path
///
/// @example webui_set_profile(my_window, "Bar", "/Home/Foo/Bar"); |
/// webui_set_profile(my_window, "", "");
pub extern fn webui_set_profile(
    window: usize,
    name: [*:0]const u8,
    path: [*:0]const u8,
) callconv(.C) void;

/// @brief Set the web browser proxy server to use. Need to be called before `webui_show()`.
///
/// @param window The window number
/// @param proxy_server The web browser proxy_server
///
/// @example webui_set_proxy(my_window, "http://127.0.0.1:8888");
pub extern fn webui_set_proxy(
    window: usize,
    proxy_server: [*:0]const u8,
) callconv(.C) void;

/// @brief Get current URL of a running window.
///
/// @param window The window number
///
/// @return Returns the full URL string
///
/// @example const url: [*:0]const u8 = webui_get_url(my_window);
pub extern fn webui_get_url(window: usize) callconv(.C) [*:0]const u8;

/// @brief Open an URL in the native default web browser.
///
/// @param url The URL to open
///
/// @example webui_open_url("https://webui.me");
pub extern fn webui_open_url(url: [*:0]const u8) callconv(.C) void;

/// @brief Allow a specific window address to be accessible from a public network.
///
/// @param window The window number
/// @param status True or False
///
/// @example webui_set_public(my_window, true);
pub extern fn webui_set_public(window: usize, status: bool) callconv(.C) void;

/// @brief Navigate to a specific URL. All clients.
///
/// @param window The window number
/// @param url Full HTTP URL
///
/// @example webui_navigate(my_window, "http://domain.com");
pub extern fn webui_navigate(window: usize, url: [*:0]const u8) callconv(.C) void;

/// @brief Navigate to a specific URL. Single client.
///
/// @param e The event struct
/// @param url Full HTTP URL
///
/// @example webui_navigate_client(e, "http://domain.com");
pub extern fn webui_navigate_client(e: *Event, url: [*:0]const u8) callconv(.C) void;

/// @brief Free all memory resources. Should be called only at the end.
///
/// @example
/// webui_wait();
/// webui_clean();
pub extern fn webui_clean() callconv(.C) void;

/// @brief Delete all local web-browser profiles folder. It should be called at the
/// end.
///
/// @example
/// webui_wait();
/// webui_delete_all_profiles();
/// webui_clean();
pub extern fn webui_delete_all_profiles() callconv(.C) void;

/// @brief Delete a specific window web-browser local folder profile.
///
/// @param window The window number
///
/// @example
/// webui_wait();
/// webui_delete_profile(my_window);
/// webui_clean();
///
/// @note This can break functionality of other windows if using the same
/// web-browser.
pub extern fn webui_delete_profile(window: usize) callconv(.C) void;

/// @brief Get the ID of the parent process (The web browser may re-create
/// another new process).
///
/// @param window The window number
///
/// @return Returns the parent process ID as integer
///
/// @example const id: usize = webui_get_parent_process_id(my_window);
pub extern fn webui_get_parent_process_id(window: usize) callconv(.C) usize;

/// @brief Get the ID of the last child process.
///
/// @param window The window number
///
/// @return Returns the child process ID as integer
///
/// @example const id: usize = webui_get_child_process_id(my_window);
pub extern fn webui_get_child_process_id(window: usize) callconv(.C) usize;

/// @brief Get the network port of a running window.
/// This can be useful to determine the HTTP link of `webui.js`
///
/// @param window The window number
///
/// @return Returns the network port of the window
///
/// @example const port: usize = webui_get_port(my_window);
pub extern fn webui_get_port(window: usize) callconv(.C) usize;

/// @brief Set a custom web-server/websocket network port to be used by WebUI.
/// This can be useful to determine the HTTP link of `webui.js` in case
/// you are trying to use WebUI with an external web-server like NGINX.
///
/// @param window The window number
/// @param port The web-server network port WebUI should use
///
/// @return Returns True if the port is free and usable by WebUI
///
/// @example const ret: bool = webui_set_port(my_window, 8080);
pub extern fn webui_set_port(window: usize, port: usize) callconv(.C) bool;

/// @brief Get an available usable free network port.
///
/// @return Returns a free port
///
/// @example const port: usize = webui_get_free_port();
pub extern fn webui_get_free_port() callconv(.C) usize;

/// @brief Control the WebUI behaviour. It's recommended to be called at the beginning.
///
/// @param option The desired option from `Config` enum
/// @param status The status of the option, `true` or `false`
///
/// @example webui_set_config(.show_wait_connection, false);
pub extern fn webui_set_config(option: Config, status: bool) callconv(.C) void;

/// @brief Control if UI events coming from this window should be processed
/// one at a time in a single blocking thread `True`, or process every event in
/// a new non-blocking thread `False`. This update single window. You can use
/// `webui_set_config(.ui_event_blocking, ...)` to update all windows.
///
/// @param window The window number
/// @param status The blocking status `true` or `false`
///
/// @example webui_set_event_blocking(my_window, true);
pub extern fn webui_set_event_blocking(window: usize, status: bool) callconv(.C) void;

/// @brief Get the HTTP mime type of a file.
///
/// @return Returns the HTTP mime string
///
/// @example const mime: [*:0]const u8 = webui_get_mime_type("foo.png");
pub extern fn webui_get_mime_type(file: [*:0]const u8) callconv(.C) [*:0]const u8;

// -- SSL/TLS -------------------------

/// @brief Set the SSL/TLS certificate and the private key content, both in PEM
/// format. This works only with `webui-2-secure` library. If set empty WebUI
/// will generate a self-signed certificate.
///
/// @param certificate_pem The SSL/TLS certificate content in PEM format
/// @param private_key_pem The private key content in PEM format
///
/// @return Returns True if the certificate and the key are valid.
///
/// @example const ret: bool = webui_set_tls_certificate("-----BEGIN
/// CERTIFICATE-----\n...", "-----BEGIN PRIVATE KEY-----\n...");
pub extern fn webui_set_tls_certificate(
    certificate_pem: [*:0]const u8,
    private_key_pem: [*:0]const u8,
) callconv(.C) bool;

// -- JavaScript ----------------------

/// @brief Run JavaScript without waiting for the response. All clients.
///
/// @param window The window number
/// @param script The JavaScript to be run
///
/// @example webui_run(my_window, "alert('Hello');");
pub extern fn webui_run(window: usize, script: [*:0]const u8) callconv(.C) void;

/// @brief Run JavaScript without waiting for the response. Single client.
///
/// @param e The event struct
/// @param script The JavaScript to be run
///
/// @example webui_run_client(e, "alert('Hello');");
pub extern fn webui_run_client(e: *Event, script: [*:0]const u8) callconv(.C) void;

/// @brief Run JavaScript and get the response back. Work only in single client mode.
/// Make sure your local buffer can hold the response.
///
/// @param window The window number
/// @param script The JavaScript to be run
/// @param timeout The execution timeout in seconds
/// @param buffer The local buffer to hold the response
/// @param buffer_length The local buffer size
///
/// @return Returns True if there is no execution error
///
/// @example const err: bool = webui_script(my_window, "return 4 + 6;", 0, my_buffer, my_buffer_size);
pub extern fn webui_script(
    window: usize,
    script: [*:0]const u8,
    timeout: usize,
    buffer: [*]u8,
    buffer_length: usize,
) callconv(.C) bool;

/// @brief Run JavaScript and get the response back. Single Client.
/// Make sure your local buffer can hold the response.
///
/// @param e The event struct
/// @param script The JavaScript to be run
/// @param timeout The execution timeout in seconds
/// @param buffer The local buffer to hold the response
/// @param buffer_length The local buffer size
///
/// @return Returns True if there is no execution error
///
/// @example const err: bool = webui_script_client(e, "return 4 + 6;", 0, my_buffer, my_buffer_size);
pub extern fn webui_script_client(
    e: *Event,
    script: [*:0]const u8,
    timeout: usize,
    buffer: [*]u8,
    buffer_length: usize,
) callconv(.C) bool;

/// @brief Choose between Deno and Nodejs as runtime for .js and .ts files.
///
/// @param window The window number
/// @param runtime .Deno | .Bun | .Nodejs | .None
///
/// @example webui_set_runtime(my_window, .Deno);
pub extern fn webui_set_runtime(window: usize, runtime: Runtime) callconv(.C) void;

/// @brief Get how many arguments there are in an event.
///
/// @param e The event struct
///
/// @return Returns the arguments count.
///
/// @example const count: usize = webui_get_count(e);
pub extern fn webui_get_count(e: *Event) callconv(.C) usize;

/// @brief Get an argument as integer at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as integer
///
/// @example const my_num: i64 = webui_get_int_at(e, 0);
pub extern fn webui_get_int_at(e: *Event, index: usize) callconv(.C) i64;

/// @brief Get the first argument as integer.
///
/// @param e The event struct
///.
/// @return Returns argument as integer
///
/// @example const my_num: i64 = webui_get_int(e);
pub extern fn webui_get_int(e: *Event) callconv(.C) i64;

/// @brief Get an argument as float at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as float
///
/// @example const my_num: f64 = webui_get_float_at(e, 0);
pub extern fn webui_get_float_at(e: *Event, index: usize) callconv(.C) f64;

/// @brief Get the first argument as float.
///
/// @param e The event struct
///
/// @return Returns argument as float
///
/// @example const my_num: f64 = webui_get_float(e);
pub extern fn webui_get_float(e: *Event) callconv(.C) f64;

/// @brief Get an argument as string at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as string
///
/// @example const my_str: [*:0]const u8 = webui_get_string_at(e, 0);
pub extern fn webui_get_string_at(e: *Event, index: usize) callconv(.C) [*:0]const u8;

/// @brief Get the first argument as string.
///
/// @param e The event struct
///
/// @return Returns argument as string
///
/// @example const my_str: [*:0]const u8 = webui_get_string(e);
pub extern fn webui_get_string(e: *Event) callconv(.C) [*:0]const u8;

/// @brief Get an argument as boolean at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as boolean
///
/// @example const my_bool: bool = webui_get_bool_at(e, 0);
pub extern fn webui_get_bool_at(e: *Event, index: usize) callconv(.C) bool;

/// @brief Get the first argument as boolean.
///
/// @param e The event struct
///
/// @return Returns argument as boolean
///
/// @example const my_bool: bool = webui_get_bool(e);
pub extern fn webui_get_bool(e: *Event) callconv(.C) bool;

/// @brief Get the size in bytes of an argument at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns size in bytes
///
/// @example const arg_len: usize = webui_get_size_at(e, 0);
pub extern fn webui_get_size_at(e: *Event, index: usize) callconv(.C) usize;

/// @brief Get size in bytes of the first argument.
///
/// @param e The event struct
///
/// @return Returns size in bytes
///
/// @example const arg_len: usize = webui_get_size(e);
pub extern fn webui_get_size(e: *Event) callconv(.C) usize;

/// @brief Return the response to JavaScript as integer.
///
/// @param e The event struct
/// @param n The integer to be send to JavaScript
///
/// @example webui_return_int(e, 123);
pub extern fn webui_return_int(e: *Event, n: i64) callconv(.C) void;

/// @brief Return the response to JavaScript as float.
///
/// @param e The event struct
/// @param f The float number to be send to JavaScript
///
/// @example webui_return_float(e, 123.456);
pub extern fn webui_return_float(e: *Event, f: f64) callconv(.C) void;

/// @brief Return the response to JavaScript as string.
///
/// @param e The event as struct
/// @param n The string to be send to JavaScript
///
/// @example webui_return_string(e, "Response...");
pub extern fn webui_return_string(e: *Event, s: [*:0]const u8) callconv(.C) void;

/// @brief Return the response to JavaScript as boolean.
///
/// @param e The event struct
/// @param n The boolean to be send to JavaScript
///
/// @example webui_return_bool(e, true);
pub extern fn webui_return_bool(e: *Event, b: bool) callconv(.C) void;

// -- Wrapper's Interface -------------

/// @brief Bind a specific HTML element click event with a function. Empty element means all events.
///
/// @param window The window number
/// @param element The element ID
/// @param func The callback as myFunc(Window, EventKind, Element, EventNumber, BindID)
///
/// @return Returns unique bind ID
///
/// @example const id: usize = webui_interface_bind(my_window, "myID", myCallback);
pub extern fn webui_interface_bind(
    window: usize,
    element: [*:0]const u8,
    func: *const fn (
        window_: usize,
        event: EventKind,
        element: [*:0]u8,
        event_number: usize,
        bind_id: usize,
    ) void,
) callconv(.C) usize;

/// @brief When using `webui_interface_bind()`, you may need this function to easily set a response.
///
/// @param window The window number
/// @param event_number The event number
/// @param response The response as string to be send to JavaScript
///
/// @example webui_interface_set_response(my_window, e.event_number, "Response...");
pub extern fn webui_interface_set_response(
    window: usize,
    event_number: usize,
    response: [*:0]const u8,
) callconv(.C) void;

/// @brief Check if the app is still running.
///
/// @return Returns True if app is running
///
/// @example const status: bool = webui_interface_is_app_running();
pub extern fn webui_interface_is_app_running() callconv(.C) bool;

/// @brief Get a unique window ID.
///
/// @param window The window number
///
/// @return Returns the unique window ID as integer
///
/// @example const id: usize = webui_interface_get_window_id(my_window);
pub extern fn webui_interface_get_window_id(window: usize) callconv(.C) usize;

/// @brief Get an argument as string at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as string
///
/// @example const my_str: [*:0]const u8 = webui_interface_get_string_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_string_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) [*:0]const u8;

/// @brief Get an argument as integer at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as integer
///
/// @example const my_num: i64 = webui_interface_get_int_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_int_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) i64;

/// @brief Get an argument as float at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as float
///
/// @example const my_float: f64 = webui_interface_get_float_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_float_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) f64;

/// @brief Get an argument as boolean at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as boolean
///
/// @example const my_bool: bool = webui_interface_get_bool_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_bool_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) bool;

/// @brief Get the size in bytes of an argument at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns size in bytes
///
/// @example const arg_len: usize = webui_interface_get_size_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_size_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) usize;
