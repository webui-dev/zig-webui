//! Call Zig from JavaScript Example
const std = @import("std");
const webui = @import("webui");

// we use @embedFile to embed html
const html = @embedFile("index.html");

pub fn main() !void {
    // Create a new WebUI window object
    var nwin = webui.newWindow();

    // Use binding function instead of standard bind function
    // binding is an advanced API that automatically handles parameter type conversion and function signature adaptation
    // It allows using native Zig function signatures without needing to handle Event pointers directly
    // Here we bind the HTML/JS "my_function_string" to Zig function getString
    _ = try nwin.binding("my_function_string", getString);
    // Equivalent using traditional bind function which requires manual Event handling
    // _ = try nwin.bind("my_function_string", my_function_string);
    
    // Bind integer handler function, binding automatically converts JS parameters to corresponding Zig types
    _ = try nwin.binding("my_function_integer", getInteger);
    // _ = try nwin.bind("my_function_integer", my_function_integer);
    
    // Bind boolean handler function, also with automatic type conversion
    _ = try nwin.binding("my_function_boolean", getBool);
    // _ = try nwin.bind("my_function_boolean", my_function_boolean);
    
    // Bind function with response, binding supports using event object directly for responses
    _ = try nwin.binding("my_function_with_response", getResponse);
    // _ = try nwin.bind("my_function_with_response", my_function_with_response);
    
    // Bind function for handling binary data, binding supports raw binary data processing
    _ = try nwin.binding("my_function_raw_binary", raw_binary);
    // _ = try nwin.bind("my_function_raw_binary", my_function_raw_binary);

    // Show the window with embedded HTML content
    try nwin.show(html);

    // Wait for all windows to close, this will block the current thread
    webui.wait();

    // Clean up all resources
    webui.clean();
}

fn getString(str1: [:0]const u8, str2: [:0]const u8) void {
    // Hello
    std.debug.print("my_function_string 1: {s}\n", .{str1});
    // World
    std.debug.print("my_function_string 2: {s}\n", .{str2});
}

fn my_function_string(e: *webui.Event) void {
    // JavaScript:
    // my_function_string('Hello', 'World`);

    // or e.getStringAt(0);
    const str_1 = e.getString();
    const str_2 = e.getStringAt(1);

    // Hello
    std.debug.print("my_function_string 1: {s}\n", .{str_1});
    // World
    std.debug.print("my_function_string 2: {s}\n", .{str_2});
}

fn getInteger(n1: i64, n2: i64, n3: i64, f1: f64) void {
    std.debug.print("number is {},{},{},{}", .{
        n1, n2, n3, f1,
    });
}

fn my_function_integer(e: *webui.Event) void {
    // JavaScript:
    // my_function_integer(123, 456, 789, 12345.6789);

    const count = e.getCount();

    std.debug.print("my_function_integer: There is {} arguments in this event\n", .{count});

    // Or e.getIntAt(0);
    const number_1 = e.getInt();
    const number_2 = e.getIntAt(1);
    const number_3 = e.getIntAt(2);

    // 123
    std.debug.print("my_function_integer 1: {}\n", .{number_1});
    // 456
    std.debug.print("my_function_integer 2: {}\n", .{number_2});
    // 789
    std.debug.print("my_function_integer 3: {}\n", .{number_3});

    const float_1 = e.getFloatAt(3);
    // 12345.6789
    std.debug.print("my_function_integer 4: {}\n", .{float_1});
}

fn getBool(b1: bool, b2: bool) void {
    std.debug.print("boolean is {},{}", .{
        b1, b2,
    });
}

fn my_function_boolean(e: *webui.Event) void {
    // JavaScript:
    // my_function_boolean(true, false);

    // Or e.getBoolAt(0);
    const status_1 = e.getBool();
    const status_2 = e.getBoolAt(1);

    // Ture
    std.debug.print("my_function_bool 1: {}\n", .{status_1});
    // False
    std.debug.print("my_function_bool 2: {}\n", .{status_2});
}

fn getResponse(e: *webui.Event,n1: i64, n2: i64) void {
    const res = n1 * n2;
    std.debug.print("my_function_with_response: {} * {} = {}\n", .{ n1, n2, res });
    // Send back the response to JavaScript
    e.returnValue(res);
}

fn my_function_with_response(e: *webui.Event) void {
    // JavaScript:
    // my_function_with_response(number, 2).then(...)

    // Or e.getIntAt(0);
    const number = e.getInt();
    const times = e.getIntAt(1);
    const res = number * times;

    std.debug.print("my_function_with_response: {} * {} = {}\n", .{ number, times, res });

    // Send back the response to JavaScript
    e.returnValue(res);
}

fn raw_binary(e: *webui.Event, raw_1: [:0]const u8, raw_2: [*]const u8) void {
    // Or e.getSizeAt(0);
    const len_1 = e.getSize() catch return;
    const len_2 = e.getSizeAt(1) catch return;

    // Print raw_1
    std.debug.print("my_function_raw_binary 1 ({} bytes): ", .{len_1});
    for (0..len_1) |i| {
        std.debug.print("0x{x} ", .{raw_1[i]});
    }
    std.debug.print("\n", .{});

    // Check raw_2 (Big)
    // [0xA1, 0x00..., 0xA2]
    var vaild = false;

    if (raw_2[0] == 0xA1 and raw_2[len_2 - 1] == 0xA2) {
        vaild = true;
    }

    // Print raw_2
    std.debug.print("my_function_raw_binary 2 big ({} bytes): valid data? {s}\n", .{
        len_2,
        if (vaild) "Yes" else "No",
    });
}

fn my_function_raw_binary(e: *webui.Event) void {
    // JavaScript:
    // my_function_raw_binary(new Uint8Array([0x41]), new Uint8Array([0x42, 0x43]));

    // Or e.getStringAt(0);
    const raw_1 = e.getString();
    const raw_2 = e.getRawAt(1);

    // Or e.getSizeAt(0);
    const len_1 = e.getSize() catch return;
    const len_2 = e.getSizeAt(1) catch return;

    // Print raw_1
    std.debug.print("my_function_raw_binary 1 ({} bytes): ", .{len_1});
    for (0..len_1) |i| {
        std.debug.print("0x{x} ", .{raw_1[i]});
    }
    std.debug.print("\n", .{});

    // Check raw_2 (Big)
    // [0xA1, 0x00..., 0xA2]
    var vaild = false;

    if (raw_2[0] == 0xA1 and raw_2[len_2 - 1] == 0xA2) {
        vaild = true;
    }

    // Print raw_2
    std.debug.print("my_function_raw_binary 2 big ({} bytes): valid data? {s}\n", .{
        len_2,
        if (vaild) "Yes" else "No",
    });
}
