const std = @import("std");
const webui = @import("webui");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    var nwin = webui.newWindow();
    _ = nwin.bind("", events);

    _ = nwin.bind("my_backend_func", my_backend_func);

    _ = nwin.setPort(8081);

    _ = nwin.show("http://localhost:8080/");

    webui.wait();
    webui.clean();
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

            std.debug.print("Starting navigation to: {s}\n", .{url});

            @memcpy(new_url[0..len], url[0..len]);

            win.navigate(new_url);
        },
        else => {},
    }
}

fn my_backend_func(e: webui.Event) void {
    const number_1 = webui.getInt(e);
    const number_2 = webui.getIntAt(e, 1);
    const number_3 = webui.getIntAt(e, 2);

    std.debug.print("my_backend_func 1: {}\n", .{number_1});
    std.debug.print("my_backend_func 2: {}\n", .{number_2});
    std.debug.print("my_backend_func 3: {}\n", .{number_3});
}
