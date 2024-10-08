//! Custom web Server - Free Port - Example
const std = @import("std");
const webui = @import("webui");

var python_server_proc: std.process.Child = undefined;
var python_running: bool = false;

var home_url: [:0]u8 = undefined;

pub fn main() !void {
    // Create new window
    var nwin = webui.newWindow();

    // Bind all events
    _ = nwin.bind("", events);
    // Bind a JS call to a Zig fn
    _ = nwin.bind("gotoPage", goto_page);

    // The `webui.js` script will be available at:
    //
    // http://localhost:[WEBUI_PORT]/webui.js
    //
    // (see [WEBUI_PORT] in: index.html, free_port_web_server.py)
    //
    // So, get and set a free port for WebUI to use:

    const webui_port: u64 = webui.getFreePort();
    std.debug.print("Free Port for webui.js: {d} \n", .{webui_port});
    // now use the port:
    _ = nwin.setPort(webui_port);

    const backend_port = webui.getFreePort();
    std.debug.print("Free Port for custom web server: {d} \n", .{backend_port});
    // now use the port:
    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    const port_argument1: []u8 = try std.fmt.bufPrintZ(&buf1, "{d}", .{backend_port});
    const port_argument2: []u8 = try std.fmt.bufPrintZ(&buf2, "{d}", .{webui_port});
    const argv = [_][]const u8{ "python", "./free_port_web_server.py", port_argument1, port_argument2 };
    python_server_proc = std.process.Child.init(&argv, std.heap.page_allocator);

    // start the SPA web server:
    startPythonWebServer();

    // Show a new window served by our custom web server (spawned above):
    var buf: [64]u8 = undefined;
    home_url = try std.fmt.bufPrintZ(&buf, "http://localhost:{d}/index.html", .{backend_port});
    _ = nwin.show(home_url);

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();

    // Free the spawned proc, port and memory
    killPythonWebServer();
}

fn startPythonWebServer() void {
    if (python_running == false) { // a better check would be a test for the process itself
        if (python_server_proc.spawn()) |_| {
            python_running = true;
            std.debug.print("Spawned python server process PID={}\n", .{python_server_proc.id});
        } else |err| {
            std.debug.print("NOT Starting python server: {}\n", .{err});
        }
    }
}

fn killPythonWebServer() void {
    if (python_running == true) {
        if (python_server_proc.kill()) |_| {
            python_running = false;
            std.debug.print("Killing python server\n", .{});
        } else |err| {
            std.debug.print("NOT Killing python server: {}\n", .{err});
        }
    }
}

// This is a Zig function that is invoked by a Javascript call,
// and in turn, calls Javascript.
fn goto_page(e: *webui.Event) void {
    // JavaScript that invoked this function: gotoPage('some-path');
    const path = e.getString();
    std.debug.print("JS invoked Zig: Navigating to page: {s}\n", .{path});
    // Now, write a Javascript call to do the navigation:
    var js: [64]u8 = std.mem.zeroes([64]u8);
    const buf = std.fmt.bufPrint(&js, "doNavigate('{s}');", .{path}) catch unreachable;
    // convert it to a Sentinel-Terminated slice
    const content: [:0]const u8 = js[0..buf.len :0];
    std.debug.print("Zig calling JS: {s}\n", .{buf});
    // Run the JavaScript
    e.getWindow().run(content);
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
            // Because we used `bind(MyWindow, "", events);`
            // WebUI will block all `href` link clicks and sent here instead.
            // We can then control the behaviour of links as needed.
            //
            // In this SPA example, the client has its own router and
            // does the navigation for all pages in page.js (2nd, 3rd, 4th).
            //
            // However, for the 1st page, we have to handle navigation here:

            // get the url string
            const url = e.getString();

            if (std.mem.eql(u8, url, home_url)) {
                // we use this to get widnow
                var win = e.getWindow();

                std.debug.print("WebUI.js is Starting navigation to: {s}\n", .{url});

                win.navigate(url);
            } else {
                std.debug.print("Client JS is navigating to: {s}\n", .{url});
                // nothing to do, client is navigating
            }
        },
        else => {
            std.debug.print("Other event {}. \n", .{e.event_type});
        },
    }
}
