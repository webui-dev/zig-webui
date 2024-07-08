//! Call Zig from JavaScript Example
const std = @import("std");
const webui = @import("webui");

// we use @embedFile to embed html
const html = @embedFile("index.html");

pub fn main() !void {
    var nwin = webui.newWindow();

    _ = nwin.bind("my_function_string", my_function_string);
    _ = nwin.bind("my_function_integer", my_function_integer);
    _ = nwin.bind("my_function_boolean", my_function_boolean);
    _ = nwin.bind("my_function_with_response", my_function_with_response);
    _ = nwin.bind("my_function_raw_binary", my_function_raw_binary);

    _ = nwin.show(html);

    webui.wait();

    webui.clean();
}

fn my_function_string(e: webui.Event) void {
    // JavaScript:
    // my_function_string('Hello', 'World`);

    // or webui.getStringAt(e, 0);
    const str_1 = webui.getString(e);
    const str_2 = webui.getStringAt(e, 1);

    // Hello
    std.debug.print("my_function_string 1: {s}\n", .{str_1});
    // World
    std.debug.print("my_function_string 2: {s}\n", .{str_2});
}

fn my_function_integer(e: webui.Event) void {
    // JavaScript:
    // my_function_integer(123, 456, 789, 12345.6789);

    const count = webui.getCount(e);

    std.debug.print("my_function_integer: There is {} arguments in this event\n", .{count});

    // Or getIntAt(e, 0);
    const number_1 = webui.getInt(e);
    const number_2 = webui.getIntAt(e, 1);
    const number_3 = webui.getIntAt(e, 2);

    // 123
    std.debug.print("my_function_integer 1: {}\n", .{number_1});
    // 456
    std.debug.print("my_function_integer 2: {}\n", .{number_2});
    // 789
    std.debug.print("my_function_integer 3: {}\n", .{number_3});

    const float_1 = webui.getFloatAt(e, 3);
    // 12345.6789
    std.debug.print("my_function_integer 4: {}\n", .{float_1});
}

fn my_function_boolean(e: webui.Event) void {
    // JavaScript:
    // my_function_boolean(true, false);

    // Or getBoolAt(e, 0);
    const status_1 = webui.getBool(e);
    const status_2 = webui.getBoolAt(e, 1);

    // Ture
    std.debug.print("my_function_bool 1: {}\n", .{status_1});
    // False
    std.debug.print("my_function_bool 2: {}\n", .{status_2});
}

fn my_function_with_response(e: webui.Event) void {
    // JavaScript:
    // my_function_with_response(number, 2).then(...)

    // Or getIntAt(e, 0);
    const number = webui.getInt(e);
    const times = webui.getIntAt(e, 1);
    const res = number * times;

    std.debug.print("my_function_with_response: {} * {} = {}\n", .{ number, times, res });

    // Send back the response to JavaScript
    e.returnValue(res);
}

fn my_function_raw_binary(e: webui.Event) void {
    // JavaScript:
    // my_function_raw_binary(new Uint8Array([0x41]), new Uint8Array([0x42, 0x43]));

    // Or getStringAt(e, 0);
    const raw_1 = webui.getString(e);
    const raw_2 = webui.getStringAt(e, 1);

    // Or getSizeAt(e, 0);
    const len_1 = webui.getSize(e);
    const len_2 = webui.getSizeAt(e, 1);

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
