//!Serve a Folder Example
const std = @import("std");
const webui = @import("webui");

var MyWindow: webui = undefined;

var MySecondWindow: webui = undefined;

pub fn main() !void {
    // Create new windows
    MyWindow = webui.newWindowWithId(1);
    MySecondWindow = webui.newWindowWithId(2);

    // Bind HTML element IDs with a C functions
    _ = MyWindow.bind("SwitchToSecondPage", switch_second_window);
    _ = MyWindow.bind("OpenNewWindow", show_second_window);
    _ = MyWindow.bind("Exit", exit_app);
    _ = MySecondWindow.bind("Exit", exit_app);

    // Bind events
    _ = MyWindow.bind("", events);

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
    _ = MyWindow.show("index.html");

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}

fn exit_app(_: webui.Event) void {
    // Close all opened windows
    webui.exit();
}

fn events(e: webui.Event) void {
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
            const allocator = std.heap.c_allocator;

            const url = e.getString();
            const win = e.getWindow();

            const new_url = allocator.dupeZ(u8, url) catch unreachable;
            defer allocator.free(new_url);

            std.debug.print("start to navigate to {s}\n", .{new_url});

            // Because we used `MyWindow.bind("", events);`
            // WebUI will block all `href` link clicks and sent here instead.
            // We can then control the behaviour of links as needed.
            win.navigate(new_url);
        },
        else => {},
    }
}

fn switch_second_window(e: webui.Event) void {
    // This function gets called every
    // time the user clicks on "SwitchToSecondPage"

    // Switch to `/second.html` in the same opened window.
    var win = e.getWindow();
    _ = win.show("second.html");
}

fn show_second_window(_: webui.Event) void {
    // This function gets called every
    // time the user clicks on "OpenNewWindow"

    // Show a new window, and navigate to `/second.html`
    // if it's already open, then switch in the same window
    _ = MySecondWindow.show("second.html");
}

var count: i32 = 0;

fn my_files_handler(filename: []const u8) ?[]const u8 {
    std.debug.print("File: {s}\n", .{filename});

    if (std.mem.eql(u8, filename, "/test.txt")) {
        // Const static file example
        // Note: The connection will drop if the content
        // does not have `<script src="/webui.js"></script>`
        return "This is a embedded file content example.";
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
            \\	    <script src="/webui.js"></script> 
            \\  </html>
        , .{count}) catch unreachable;

        return buf;
    }

    return null;
}
