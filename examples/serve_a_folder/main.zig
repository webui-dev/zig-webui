//!Serve a Folder Example
const std = @import("std");
const webui = @import("webui");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var MyWindow: webui = undefined;

var MySecondWindow: webui = undefined;

pub fn main() !void {
    MyWindow = webui.newWindowWithId(1);
    MySecondWindow = webui.newWindowWithId(2);

    _ = MyWindow.bind("SwitchToSecondPage", switch_second_window);
    _ = MyWindow.bind("OpenNewWindow", show_second_window);

    _ = MyWindow.bind("Exit", exit_app);

    _ = MySecondWindow.bind("Exit", exit_app);

    _ = MyWindow.bind("", events);

    MyWindow.setRuntime(.Deno);

    MyWindow.setFileHandler(my_files_handler);

    MyWindow.setSize(800, 800);

    MyWindow.setPosition(200, 200);

    _ = MyWindow.show("index.html");

    webui.wait();

    webui.clean();
}

fn exit_app(_: webui.Event) void {
    webui.exit();
}

fn events(e: webui.Event) void {
    switch (e.event_type) {
        .EVENT_CONNECTED => {
            std.debug.print("Connected. \n", .{});
        },
        .EVENT_DISCONNECTED => {
            std.debug.print("Disconnected. \n", .{});
        },
        .EVENT_MOUSE_CLICK => {
            std.debug.print("Click. \n", .{});
        },
        .EVENT_NAVIGATION => {
            const allocator = gpa.allocator();

            defer {
                const deinit_status = gpa.deinit();

                if (deinit_status == .leak) @panic("TEST FAIL");
            }

            const url = webui.getString(e);
            const len = webui.str_len(url);

            var tmp_e = e;
            var win = tmp_e.getWindow();

            const new_url = allocator.allocSentinel(u8, len, 0) catch unreachable;
            defer allocator.free(new_url);

            @memcpy(new_url[0..len], url[0..len]);

            win.navigate(new_url);
        },
        else => {},
    }
}

fn switch_second_window(e: webui.Event) void {
    var tmp_e = e;
    var win = tmp_e.getWindow();
    _ = win.show("second.html");
}

fn show_second_window(_: webui.Event) void {
    _ = MySecondWindow.show("second.html");
}

var text_1 = "This is a embedded file content example.".*;

var count: i32 = 0;

fn my_files_handler(filename: []const u8) ?[]u8 {
    std.debug.print("File: {s}\n", .{filename});

    if (std.mem.eql(u8, filename, "/test.txt")) {
        return &text_1;
    } else if (std.mem.eql(u8, filename, "/dynamic.html")) {
        var dynamic_content = webui.malloc(1024);

        for (0..dynamic_content.len) |i| {
            dynamic_content[i] = 0;
        }

        count += 1;

        const buf = std.fmt.bufPrint(dynamic_content,
            \\  <html>
            \\      This is a dynamic file content example. <br>
            \\	    Count: {} <a href="dynamic.html">[Refresh]</a><br>
            \\	    <script src="webui.js"></script> 
            \\  </html>
        , .{count}) catch unreachable;

        return buf;
    }

    return null;
}
