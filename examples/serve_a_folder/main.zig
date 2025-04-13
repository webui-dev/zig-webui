//!Serve a Folder Example
const std = @import("std");
const webui = @import("webui");
const test_txt = @embedFile("test.txt");
const dynamic_txt = @embedFile("dynamic.txt");

var MyWindow: webui = undefined;
var MySecondWindow: webui = undefined;

pub fn main() !void {
    // Create new windows
    MyWindow = try webui.newWindowWithId(1);
    MySecondWindow = try webui.newWindowWithId(2);

    // Bind HTML element IDs with a C functions
    _ = try MyWindow.bind("SwitchToSecondPage", switch_second_window);
    _ = try MyWindow.bind("OpenNewWindow", show_second_window);
    _ = try MyWindow.bind("Exit", exit_app);
    _ = try MySecondWindow.bind("Exit", exit_app);

    // Bind events
    _ = try MyWindow.bind("", events);

    // Set the `.ts` and `.js` runtime
    // webui_set_runtime(MyWindow, NodeJS);
    // webui_set_runtime(MyWindow, Bun);
    MyWindow.setRuntime(.Deno);

    // Set a custom files handler
    MyWindow.setFileHandler(my_files_handler);

    // Set window size
    MyWindow.setSize(800, 800);

    // Set window position
    MyWindow.setPosition(200, 200);

    // Show a new window
    // webui_set_root_folder(MyWindow, "_MY_PATH_HERE_");
    // webui_show_browser(MyWindow, "index.html", Chrome);
    try MyWindow.show("index.html");

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}

fn exit_app(_: *webui.Event) void {
    // Close all opened windows
    webui.exit();
}

fn events(e: *webui.Event) void {
    // This function gets called every time
    // there is an event
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
            const url = e.getString();
            const win = e.getWindow();

            std.debug.print("start to navigate to {s}\n", .{url});

            // Because we used `MyWindow.bind("", events);`
            // WebUI will block all `href` link clicks and sent here instead.
            // We can then control the behaviour of links as needed.
            win.navigate(url);
        },
        else => {},
    }
}

fn switch_second_window(e: *webui.Event) void {
    // This function gets called every
    // time the user clicks on "SwitchToSecondPage"

    // Switch to `/second.html` in the same opened window.
    e.getWindow().show("second.html") catch return;
}

fn show_second_window(_: *webui.Event) void {
    // This function gets called every
    // time the user clicks on "OpenNewWindow"

    // Show a new window, and navigate to `/second.html`
    // if it's already open, then switch in the same window
    MySecondWindow.show("second.html") catch return;
}

var count: i32 = 0;

fn my_files_handler(filename: []const u8) ?[]const u8 {
    std.debug.print("File: {s}\n", .{filename});

    if (std.mem.eql(u8, filename, "/test.txt")) {
        // Const static file example
        return test_txt;
    } else if (std.mem.eql(u8, filename, "/dynamic.html")) {
        const body = webui.malloc(1024) catch unreachable;
        defer webui.free(body);
        const header_and_body = webui.malloc(1024) catch unreachable;

        count += 1;

        const buf = std.fmt.bufPrint(body, dynamic_txt, .{count}) catch unreachable;

        const content = std.fmt.bufPrint(header_and_body,
            \\HTTP/1.1 200 OK
            \\Content-Type: text/html
            \\Content-Length: {}
            \\
            \\{s}
        , .{ buf.len, buf }) catch unreachable;

        // Generate header + body

        // By allocating resources using webui.malloc()
        // WebUI will automaticaly free the resources.
        return content;
    }

    return null;
}
