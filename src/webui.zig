//! This is Zig Wrapping for [Webui](https://github.com/webui-dev/webui),
//! Zig-WebUI Library
//!
//! WebSite: [http://webui.me](http://webui.me),
//! Github: [https://github.com/webui-dev/zig-webui](https://github.com/webui-dev/zig-webui)
//!
//! Copyright (c) 2020-2024 [Jinzhongjia](https://github.com/jinzhongjia),
//! Licensed under MIT License.

const std = @import("std");
const builtin = @import("builtin");
const flags = @import("flags");

const WebUI = @cImport({
    @cInclude("webui.h");
});

const comptimePrint = std.fmt.comptimePrint;

const Self = @This();

/// Browsers for webui
pub const Browsers = enum(u8) {
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
};

/// runtime for js
pub const Runtimes = enum(u8) {
    /// 0. Prevent WebUI from using any runtime for .js and .ts files
    None = 0,
    /// 1. Use Deno runtime for .js and .ts files
    Deno,
    /// 2. Use Nodejs runtime for .js files
    NodeJS,
};

/// Events for webui
pub const Events = enum(u8) {
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

pub const Config = enum(u8) {
    // Control if `show()`,`webui_show_browser`,`webui_show_wv` should wait
    // for the window to connect before returns or not.
    // Default: True
    show_wait_connection = 0,
};

/// Get the string length.
/// This function is exposed to process the string returned by c
pub fn str_len(str: anytype) usize {
    const t = @TypeOf(str);
    switch (t) {
        [*c]u8, [*c]const u8, [*:0]u8, [*:0]const u8 => {
            return std.mem.len(str);
        },
        else => {
            const err_msg = comptimePrint("type of str ({}) should be [*c]u8 or [*c]const u8", .{t});
            @compileError(err_msg);
        },
    }
}

/// Event, the communication between webui and browser depends on this
pub const Event = struct {
    /// Window handle.
    /// Please do not assign values ​​manually unless you know what you are doing
    window_handle: usize,
    /// Event's type, more info to see `Events`
    event_type: Events,
    /// the broswer HTML element ID.
    /// not recommended to modify this value
    element: []u8,
    /// Internal WebUI.
    /// treated as sequence number of event
    event_number: usize,
    /// Bind ID
    bind_id: usize,

    /// c raw webui_event_t.
    /// don't modify it directly
    e: *WebUI.webui_event_t,

    /// get window through Event
    pub fn getWindow(self: Event) Self {
        return .{
            .window_handle = self.window_handle,
        };
    }

    /// convert zig Event to c webui_event_t,
    /// you won't use this
    pub fn convertToWebUIEventT(self: *Event) WebUI.webui_event_t {
        return WebUI.webui_event_t{
            .window = self.window_handle,
            .event_type = self.event_type,
            .element = @ptrCast(self.element.ptr),
            .event_number = self.event_number,
            .bind_id = self.bind_id,
        };
    }

    /// convert c webui_event_t to zig event
    /// you also won't use this
    pub fn convertWebUIEventT2(event: *WebUI.webui_event_t) Event {
        const len = str_len(event.element);

        return .{
            .window_handle = event.window,
            .event_type = @enumFromInt(event.event_type),
            .element = event.element[0..len],
            .event_number = event.event_number,
            .bind_id = event.bind_id,
            .e = event,
        };
    }

    /// Return the response to JavaScript as integer.
    pub fn returnInt(e: Event, n: i64) void {
        WebUI.webui_return_int(e.e, @intCast(n));
    }

    /// Return the response to JavaScript as float.
    pub fn returnFloat(e: Event, f: f64) void {
        WebUI.webui_return_float(e.e, f);
    }

    /// Return the response to JavaScript as string.
    pub fn returnString(e: Event, str: [:0]const u8) void {
        WebUI.webui_return_string(e.e, @ptrCast(str.ptr));
    }

    /// Return the response to JavaScript as boolean.
    pub fn returnBool(e: Event, b: bool) void {
        WebUI.webui_return_bool(e.e, b);
    }

    /// a convenient function to return value
    /// no need to care about the function name, you just need to call returnValue
    pub fn returnValue(e: Event, val: anytype) void {
        const T = @TypeOf(val);
        const type_info = @typeInfo(T);
        switch (type_info) {
            .Pointer => |pointer| {
                if (pointer.size == .Slice and
                    pointer.child == u8 and
                    (if (pointer.sentinel) |sentinel| @as(*u8, @ptrCast(sentinel)).* == 0 else false))
                {
                    e.returnString(val);
                } else {
                    const err_msg = comptimePrint("val's type ({}), only support []const u8 for Pointer!", .{T});
                    @compileError(err_msg);
                }
            },
            .Int => |int| {
                const bits = int.bits;
                const is_signed = int.signedness == .signed;
                if (is_signed and bits <= 64) {
                    e.returnInt(@intCast(val));
                } else if (!is_signed and bits <= 63) {
                    e.returnInt(@intCast(val));
                } else {
                    const err_msg = comptimePrint("val's type ({}), out of i64", .{T});
                    @compileError(err_msg);
                }
            },
            .Bool => {
                e.returnBool(val);
            },
            .Float => {
                e.returnFloat(val);
            },
            else => {
                const err_msg = comptimePrint("val's type ({}), only support int, bool, string([]const u8)!", .{T});
                @compileError(err_msg);
            },
        }
    }
};

/// the window number,
/// please not modify this value
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
        if (comptime builtin.zig_version.minor == 11) {
            std.os.exit(1);
        } else if (comptime builtin.zig_version.minor == 12) {
            std.posix.exit(1);
        }
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
/// Empty element means all events,
/// `element` is The HTML ID,
/// `func` is The callback function,
/// Returns a unique bind ID.
pub fn bind(self: *Self, element: [:0]const u8, comptime func: fn (e: Event) void) usize {
    const tmp_struct = struct {
        fn handle(tmp_e: [*c]WebUI.webui_event_t) callconv(.C) void {
            func(Event.convertWebUIEventT2(tmp_e));
        }
    };
    return WebUI.webui_bind(self.window_handle, @ptrCast(element.ptr), tmp_struct.handle);
}

/// Get the recommended web browser ID to use. If you
/// are already using one, this function will return the same ID.
pub fn getBestBrowser(self: *Self) Browsers {
    const res = WebUI.webui_get_best_browser(self.window_handle);
    return @enumFromInt(res);
}

/// Show a window using embedded HTML, or a file.
/// If the window is already open, it will be refreshed.
/// Returns True if showing the window is successed
/// `content` is the html which will be shown
pub fn show(self: *Self, content: [:0]const u8) bool {
    return WebUI.webui_show(self.window_handle, @ptrCast(content.ptr));
}

/// Same as `show()`. But using a specific web browser
/// Returns True if showing the window is successed
pub fn showBrowser(self: *Self, content: [:0]const u8, browser: Browsers) bool {
    return WebUI.webui_show_browser(self.window_handle, @ptrCast(content.ptr), @intFromEnum(browser));
}

/// Show a WebView window using embedded HTML, or a file. If the window is already
/// opend, it will be refreshed. Note: Win32 need `WebView2Loader.dll`.
/// Returns True if if showing the WebView window is successed.
pub fn showWv(self: *Self, content: [:0]const u8) bool {
    return WebUI.webui_show_wv(self.window_handle, @ptrCast(content.ptr));
}

/// Set the window in Kiosk mode (Full screen)
pub fn setKiosk(self: *Self, status: bool) void {
    WebUI.webui_set_kiosk(self.window_handle, status);
}

/// Wait until all opened windows get closed.
/// This function should be **called** at the end, it will **block** the current thread
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

/// Close all open windows.
/// `wait()` will return (Break)
pub fn exit() void {
    WebUI.webui_exit();
}

/// Set the web-server root folder path for a specific window.
pub fn setRootFolder(self: *Self, path: [:0]const u8) bool {
    return WebUI.webui_set_root_folder(self.window_handle, @ptrCast(path.ptr));
}

/// Set the web-server root folder path for all windows.
/// Should be used before `show()`.
pub fn setDefaultRootFolder(path: [:0]const u8) bool {
    return WebUI.webui_set_default_root_folder(@ptrCast(path.ptr));
}

/// Set a custom handler to serve files.
pub fn setFileHandler(self: *Self, comptime handler: fn (filename: []const u8) ?[]u8) void {
    const tmp_struct = struct {
        fn handle(tmp_filename: [*c]const u8, length: [*c]c_int) callconv(.C) ?*const anyopaque {
            const len = str_len(tmp_filename);
            const content = handler(tmp_filename[0..len]);
            if (content) |val| {
                length.* = @intCast(val.len);
                return @ptrCast(val.ptr);
            }

            return null;
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
pub fn setIcon(self: *Self, icon: [:0]const u8, icon_type: [:0]const u8) void {
    WebUI.webui_set_icon(self.window_handle, @ptrCast(icon.ptr), @ptrCast(icon_type));
}

/// Base64 encoding. Use this to safely send text based data to the UI. If
/// it fails it will return NULL.
pub fn encode(str: [:0]const u8) ?[]u8 {
    const ptr = WebUI.webui_encode(@ptrCast(str.ptr));
    if (ptr == null) {
        return null;
    }
    const len = str_len(ptr);
    return ptr[0..len];
}

/// Base64 decoding.
/// Use this to safely decode received Base64 text from the UI.
/// If it fails it will return NULL.
pub fn decode(str: [:0]const u8) ?[]u8 {
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
/// In general, you should not use this function
pub fn malloc(size: usize) []u8 {
    const ptr = WebUI.webui_malloc(size);
    return @as([*]u8, @ptrCast(ptr))[0..size];
}

/// Safely send raw data to the UI.
pub fn sendRaw(self: *Self, js_func: [:0]const u8, raw: []u8) void {
    WebUI.webui_send_raw(self.window_handle, @ptrCast(js_func.ptr), @ptrCast(raw.ptr), raw.len);
}

/// Set a window in hidden mode.
/// Should be called before `show()`
pub fn setHide(self: *Self, status: bool) void {
    WebUI.webui_set_hide(self.window_handle, status);
}

/// Set the window size.
pub fn setSize(self: *Self, width: u32, height: u32) void {
    WebUI.webui_set_size(self.window_handle, @intCast(width), @intCast(height));
}

/// Set the window position.
pub fn setPosition(self: *Self, x: u32, y: u32) void {
    WebUI.webui_set_position(self.window_handle, @intCast(x), @intCast(y));
}

/// Set the web browser profile to use.
/// An empty `name` and `path` means the default user profile.
/// Need to be called before `show()`.
pub fn setProfile(self: *Self, name: [:0]const u8, path: [:0]const u8) void {
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
pub fn navigate(self: *Self, url: [:0]const u8) void {
    WebUI.webui_navigate(self.window_handle, @ptrCast(url.ptr));
}

/// Free all memory resources.
/// Should be called only at the end.
pub fn clean() void {
    WebUI.webui_clean();
}

/// Delete all local web-browser profiles folder.
/// It should called at the end.
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
/// Returns True if the port is free and usable by WebUI
pub fn setPort(self: *Self, port: usize) bool {
    return WebUI.webui_set_port(self.window_handle, port);
}

/// Control the WebUI behaviour. It's better to call at the beginning.
pub fn setConfig(option: Config, status: bool) void {
    WebUI.webui_set_config(@intCast(@intFromEnum(option)), status);
}

/// Set the SSL/TLS certificate and the private key content,
/// both in PEM format.
/// This works only with `webui-2-secure` library.
/// If set empty WebUI will generate a self-signed certificate.
pub fn setTlsCertificate(certificate_pem: [:0]const u8, private_key_pem: [:0]const u8) bool {
    if (comptime !flags.enableTLS) {
        @panic("not enable tls");
    }
    return WebUI.webui_set_tls_certificate(@ptrCast(certificate_pem.ptr), @ptrCast(private_key_pem.ptr));
}

/// Run JavaScript without waiting for the response.
pub fn run(self: *Self, script_content: [:0]const u8) void {
    WebUI.webui_run(self.window_handle, @ptrCast(script_content.ptr));
}

/// Run JavaScript and get the response back
/// Make sure your local buffer can hold the response.
/// Return True if there is no execution error
pub fn script(self: *Self, script_content: [:0]const u8, timeout: usize, buffer: []u8) bool {
    return WebUI.webui_script(self.window_handle, @ptrCast(script_content.ptr), timeout, @ptrCast(buffer.ptr), buffer.len);
}

/// Chose between Deno and Nodejs as runtime for .js and .ts files.
pub fn setRuntime(self: *Self, runtime: Runtimes) void {
    WebUI.webui_set_runtime(self.window_handle, @intFromEnum(runtime));
}

/// Get how many arguments there are in an event
pub fn getCount(e: Event) usize {
    return WebUI.webui_get_count(e.e);
}

/// Get an argument as integer at a specific index
pub fn getIntAt(e: Event, index: usize) i64 {
    return @intCast(WebUI.webui_get_int_at(e.e, index));
}

/// Get the first argument as integer
pub fn getInt(e: Event) i64 {
    return @intCast(WebUI.webui_get_int(e.e));
}

/// Get an argument as float at a specific index
pub fn getFloatAt(e: Event, index: usize) f64 {
    return WebUI.webui_get_float_at(e.e, index);
}

/// Get the first argument as float
pub fn getFloat(e: Event) f64 {
    WebUI.webui_get_float(e.e);
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

/// **deprecated**: use Event.returnInt
/// Return the response to JavaScript as integer.
pub fn returnInt(_: Event, _: i64) void {
    @compileError("pleaser use Event.returnInt, this will be removed when zig-webui release");
}

/// **deprecated**: use Event.returnString
/// Return the response to JavaScript as string.
pub fn returnString(_: Event, _: [:0]const u8) void {
    @compileError("pleaser use Event.returnString, this will be removed when zig-webui release");
}

/// **deprecated**: use Event.returnBool
/// Return the response to JavaScript as boolean.
pub fn returnBool(_: Event, _: bool) void {
    @compileError("pleaser use Event.returnBool, this will be removed when zig-webui release");
}

/// Bind a specific HTML element click event with a function.
/// Empty element means all events.
pub fn interfaceBind(self: *Self, element: [:0]const u8, comptime callback: fn (window_handle: usize, event_type: usize, element: []u8, event_number: usize, bind_id: usize) void) void {
    const tmp_struct = struct {
        fn handle(tmp_window: usize, tmp_event_type: usize, tmp_element: [*c]u8, tmp_event_number: usize, tmp_bind_id: usize) callconv(.C) void {
            const len = str_len(tmp_element);
            callback(tmp_window, tmp_event_type, tmp_element[0..len], tmp_event_number, tmp_bind_id);
        }
    };
    WebUI.webui_interface_bind(self.window_handle, @ptrCast(element.ptr), tmp_struct.handle);
}

/// When using `interfaceBind()`,
/// you may need this function to easily set a response.
pub fn interfaceSetResponse(self: *Self, event_number: usize, response: [:0]const u8) void {
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
pub fn interfaceGetIntAt(self: *Self, event_number: usize, index: usize) i64 {
    const n = WebUI.webui_interface_get_int_at(self.window_handle, event_number, index);
    return @intCast(n);
}

/// Get an argument as boolean at a specific index
pub fn interfaceGetBoolAt(self: *Self, event_number: usize, index: usize) bool {
    return WebUI.webui_interface_get_bool_at(self.window_handle, event_number, index);
}

/// Get the size in bytes of an argument at a specific index
pub fn interfaceGetSizeAt(self: *Self, event_number: usize, index: usize) usize {
    return WebUI.webui_interface_get_size_at(self.window_handle, event_number, index);
}

//////

/// a very convenient function for binding callback.
/// you just need to pase a function to get param.
/// no need to care webui param api.
pub fn binding(self: *Self, element: [:0]const u8, comptime callback: anytype) usize {
    const T = @TypeOf(callback);
    const TInfo = @typeInfo(T);

    if (TInfo != .Fn) {
        const err_msg = comptimePrint("callback's type ({}), it must be a function!", .{T});
        @compileError(err_msg);
    }

    const fnInfo = TInfo.Fn;
    if (fnInfo.return_type != void) {
        const err_msg = comptimePrint("callback's return type ({}), it must be void!", .{fnInfo.return_type});
        @compileError(err_msg);
    }

    if (fnInfo.is_generic) {
        const err_msg = comptimePrint("callback's type ({}), it can not be a generic function!", .{T});
        @compileError(err_msg);
    }

    if (fnInfo.is_var_args) {
        const err_msg = comptimePrint("callback's type ({}), it can not have variable args!", .{T});
        @compileError(err_msg);
    }

    const tmp_struct = struct {
        const tup_t = fnParamsToTuple(fnInfo.params);

        fn handle(e: Event) void {
            var param_tup: tup_t = undefined;

            inline for (fnInfo.params, 0..fnInfo.params.len) |param, i| {
                if (param.type) |tt| {
                    const paramTInfo = @typeInfo(tt);
                    switch (paramTInfo) {
                        .Struct => {
                            if (tt != Event) {
                                const err_msg = comptimePrint("the struct type is ({}), the struct type you can use only is Event in params!", .{tt});
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
                                const err_msg = comptimePrint("the pointer type is ({}), not support other type for pointer param!", .{tt});
                                @compileError(err_msg);
                            }
                            const str_ptr = getStringAt(e, i);
                            const tmp_str_len = getSizeAt(e, i);
                            const str: []const u8 = str_ptr[0..tmp_str_len];
                            param_tup[i] = str;
                        },
                        else => {
                            const err_msg = comptimePrint("type is ({}), only support these types: Event, Bool, Int, []u8!", .{tt});
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
