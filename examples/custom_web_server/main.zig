//! Custom web Server Example
const std = @import("std");
const webui = @import("webui");

pub fn main() !void {
    // Create new windows
    var nwin = webui.newWindow();

    // Bind all events
    _ = try nwin.bind("", events);

    // Bind HTML elements with Zig functions
    _ = try nwin.bind("my_backend_func", my_backend_func);

    // Set the web-server/WebSocket port that WebUI should
    // use. This means `webui.js` will be available at:
    // http://localhost:MY_PORT_NUMBER/webui.js
    try nwin.setPort(8081);

    // Show a new window and show our custom web server
    // Assuming the custom web server is running on port
    // 8080...
    try nwin.show("http://localhost:8080/");

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
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

            // get the url string
            const url = e.getString();

            // we use this to get widnow
            var win = e.getWindow();

            std.debug.print("Starting navigation to: {s}\n", .{url});

            // Because we used `bind(MyWindow, "", events);`
            // WebUI will block all `href` link clicks and sent here instead.
            // We can then control the behaviour of links as needed.

            win.navigate(url);
        },
        else => {},
    }
}

fn my_backend_func(e: *webui.Event) void {
    // JavaScript:
    // my_backend_func(123, 456, 789);
    // or webui.my_backend_func(...);

    const number_1 = e.getInt();
    const number_2 = e.getIntAt(1);
    const number_3 = e.getIntAt(2);

    std.debug.print("my_backend_func 1: {}\n", .{number_1});
    std.debug.print("my_backend_func 2: {}\n", .{number_2});
    std.debug.print("my_backend_func 3: {}\n", .{number_3});
}
