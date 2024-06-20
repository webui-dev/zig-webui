//! Call JavaScript from Zig Example
const std = @import("std");
const webui = @import("webui");
const html = @embedFile("index.html");

pub fn main() !void {
    // Create a window
    var nwin = webui.newWindow();

    // Bind HTML elements with C functions
    _ = nwin.bind("my_function_count", my_function_count);
    _ = nwin.bind("my_function_exit", my_function_exit);

    // Show the window
    _ = nwin.show(html);
    // _ = nwin.showBrowser(html, .Chrome);

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}

fn my_function_count(e: webui.Event) void {
    // This function gets called every time the user clicks on "my_function_count"

    var new_e = e;

    // Create a buffer to hold the response
    var response = std.mem.zeroes([64]u8);

    var win = new_e.getWindow();

    // Run JavaScript
    if (!win.script("return GetCount();", 0, &response)) {
        if (!win.isShown()) {
            std.debug.print("window closed\n", .{});
        } else {
            std.debug.print("js error:{s}\n", .{response});
        }
    }

    const res_buf = response[0..std.mem.len(@as([*:0]u8, @ptrCast(&response)))];

    // Get the count
    var tmp_count = std.fmt.parseInt(i32, res_buf, 10) catch |err| blk: {
        std.log.err("error is {}", .{err});
        break :blk -50;
    };

    // Increment
    tmp_count += 1;

    // Generate a JavaScript
    var js: [64]u8 = std.mem.zeroes([64]u8);
    const buf = std.fmt.bufPrint(&js, "SetCount({});", .{tmp_count}) catch unreachable;

    // convert to a Sentinel-Terminated slice
    const content: [:0]const u8 = js[0..buf.len :0];

    // Run JavaScript (Quick Way)
    win.run(content);
}

fn my_function_exit(_: webui.Event) void {

    // Close all opened windows
    webui.exit();
}
