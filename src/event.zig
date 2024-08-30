const std = @import("std");
const builtin = @import("builtin");
const flags = @import("flags");

const webui = @import("webui.zig");
const WebUI = @import("header.zig");
const tools = @import("tools.zig");
const meta = @import("meta.zig");

const comptimePrint = std.fmt.comptimePrint;

/// Event, the communication between webui and browser depends on this
pub const Event = struct {
    /// Window handle.
    /// Please do not assign values manually unless you know what you are doing
    window_handle: usize,
    /// Event's type, more info to see `Events`
    event_type: meta.Events,
    /// the broswer HTML element ID.
    /// not recommended to modify this value
    element: []u8,
    /// Internal WebUI.
    /// treated as sequence number of event
    event_number: usize,
    /// Bind ID
    bind_id: usize,
    /// Client's unique ID
    client_id: usize,
    /// Client's connection ID
    connection_id: usize,
    /// Client's full cookies
    cookies: []u8,

    /// c raw webui_event_t.
    /// don't modify it directly
    e: *WebUI.webui_event_t,

    /// get window through Event
    pub fn getWindow(self: Event) webui {
        return .{
            .window_handle = self.window_handle,
        };
    }

    /// convert zig Event to c webui_event_t,
    /// you won't use this
    pub fn convertToWebUIEventT(self: Event) WebUI.webui_event_t {
        return WebUI.webui_event_t{
            .window = self.window_handle,
            .event_type = self.event_type,
            .element = @ptrCast(self.element.ptr),
            .event_number = self.event_number,
            .bind_id = self.bind_id,
            .client_id = self.client_id,
            .connection_id = self.connection_id,
            .cookies = @ptrCast(self.cookies.ptr),
        };
    }

    /// convert c webui_event_t to zig event
    /// you also won't use this
    pub fn convertWebUIEventT2(event: *WebUI.webui_event_t) Event {
        const element: []u8 = event.element[0..tools.str_len(event.element)];
        const cookies: []u8 = event.cookies[0..tools.str_len(event.cookies)];

        return .{
            .window_handle = event.window,
            .event_type = @enumFromInt(event.event_type),
            .element = element,
            .event_number = event.event_number,
            .bind_id = event.bind_id,
            .client_id = event.client_id,
            .connection_id = event.connection_id,
            .cookies = cookies,
            .e = event,
        };
    }

    /// Show a window using embedded HTML, or a file.
    /// If the window is already open, it will be refreshed. Single client.
    pub fn showClient(self: Event, content: [:0]const u8) bool {
        return WebUI.webui_show_client(self.e, @ptrCast(content.ptr));
    }

    /// Close a specific client.
    pub fn closeClient(self: Event) void {
        WebUI.webui_close_client(self.e);
    }

    /// Safely send raw data to the UI. Single client.
    pub fn sendRawClient(self: Event, function: [:0]const u8, buffer: []const u8) void {
        WebUI.webui_send_raw_client(self.e, @ptrCast(function.ptr), @ptrCast(buffer.ptr), buffer.len);
    }

    /// Navigate to a specific URL. Single client.
    pub fn navigateClient(self: Event, url: [:0]const u8) void {
        WebUI.webui_navigate_client(self.e, @ptrCast(url.ptr));
    }

    /// Run JavaScript without waiting for the response. Single client.
    pub fn runClient(self: Event, script_content: [:0]const u8) void {
        WebUI.webui_run_client(self.e, @ptrCast(script_content.ptr));
    }

    /// Run JavaScript and get the response back. Single client.
    /// Make sure your local buffer can hold the response.
    pub fn scriptClient(self: Event, script_content: [:0]const u8, timeout: usize, buffer: []u8) bool {
        return WebUI.webui_script_client(
            self.e,
            @ptrCast(script_content.ptr),
            timeout,
            @ptrCast(buffer.ptr),
            buffer.len,
        );
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

        const is_dev = builtin.zig_version.minor > 13;

        switch (type_info) {
            if (is_dev) .pointer else .Pointer => |pointer| {
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
             if (is_dev) .int else .Int => |int| {
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
            if (is_dev) .bool else .Bool => e.returnBool(val),
            if (is_dev) .float else .Float => e.returnFloat(val),
            else => {
                const err_msg = comptimePrint("val's type ({}), only support int, bool, string([]const u8)!", .{T});
                @compileError(err_msg);
            },
        }
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
    pub fn getStringAt(e: Event, index: usize) [:0]const u8 {
        const ptr = WebUI.webui_get_string_at(e.e, index);
        const len = tools.str_len(ptr);
        return ptr[0..len :0];
    }

    /// Get the first argument as string
    pub fn getString(e: Event) [:0]const u8 {
        const ptr = WebUI.webui_get_string(e.e);
        const len = tools.str_len(ptr);
        return ptr[0..len :0];
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
};
