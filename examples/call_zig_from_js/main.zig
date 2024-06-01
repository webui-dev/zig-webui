const std = @import("std");
const webui = @import("webui");
// we use @embedFile to embed html
const html = @embedFile("index.html");

pub fn main() !void {
    var nwin = webui.newWindow();

    _ = nwin.bind("MyID_One", my_function_string);
    _ = nwin.bind("MyID_Two", my_function_integer);
    _ = nwin.bind("MyID_Three", my_function_boolean);
    _ = nwin.bind("MyID_Four", my_function_with_response);
    _ = nwin.bind("MyID_RawBinary", my_function_raw_binary);

    _ = nwin.show(html);

    webui.wait();

    webui.clean();
}

fn my_function_string(e: webui.Event) void {
    const str_1 = webui.getString(e);
    const str_2 = webui.getStringAt(e, 1);
    // const str_3 = webui.getStringAt(e, 2);

    std.debug.print("my_function_string 1: {s}\n", .{str_1[0..webui.str_len(str_1)]});
    std.debug.print("my_function_string 2: {s}\n", .{str_2[0..webui.str_len(str_2)]});
    // std.debug.print("my_function_string 3: {s}\n", .{str_3});
}

fn my_function_integer(e: webui.Event) void {
    const count = webui.getCount(e);

    std.debug.print("my_function_integer: There is {} arguments in this event\n", .{count});

    const number_1 = webui.getInt(e);
    const number_2 = webui.getIntAt(e, 1);
    const number_3 = webui.getIntAt(e, 2);

    std.debug.print("my_function_integer 1: {}\n", .{number_1});
    std.debug.print("my_function_integer 2: {}\n", .{number_2});
    std.debug.print("my_function_integer 3: {}\n", .{number_3});

    const float_1 = webui.getFloatAt(e, 3);
    std.debug.print("my_function_integer 4: {}\n", .{float_1});
}

fn my_function_boolean(e: webui.Event) void {
    const status_1 = webui.getBool(e);
    const status_2 = webui.getBoolAt(e, 1);

    std.debug.print("my_function_bool 1: {}\n", .{status_1});
    std.debug.print("my_function_bool 2: {}\n", .{status_2});
}

fn my_function_with_response(e: webui.Event) void {
    const number = webui.getInt(e);
    const times = webui.getIntAt(e, 1);
    const res = number * times;

    std.debug.print("my_function_with_response: {} * {} = {}\n", .{ number, times, res });

    e.returnValue(res);
}

fn my_function_raw_binary(e: webui.Event) void {
    const raw_1 = webui.getString(e);
    const raw_2 = webui.getStringAt(e, 1);

    const len_1 = webui.getSize(e);
    const len_2 = webui.getSizeAt(e, 1);

    std.debug.print("my_function_raw_binary 1 ({} bytes): ", .{len_1});
    for (0..len_1) |i| {
        std.debug.print("0x{x} ", .{raw_1[i]});
    }
    std.debug.print("\n", .{});

    var vaild = false;

    if (raw_2[0] == 0xA1 and raw_2[len_2 - 1] == 0xA2) {
        vaild = true;
    }

    std.debug.print("my_function_raw_binary 2 big ({} bytes): valid data? {s}\n", .{
        len_2,
        if (vaild) "Yes" else "No",
    });
}
