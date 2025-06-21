//! Public Network Access Example
const std = @import("std");
const webui = @import("webui");

// embed the html
const private_html = @embedFile("private.html");
const public_html = @embedFile("public.html");

// two windows
var private_window: webui = undefined;
var public_window: webui = undefined;

fn app_exit(_: *webui.Event) void {
    webui.exit();
}

fn public_window_events(e: *webui.Event) void {
    if (e.event_type == .EVENT_CONNECTED) {
        // New connection
        private_window.run("document.getElementById(\"Logs\").value += \"New connection.\\n\";");
    } else if (e.event_type == .EVENT_DISCONNECTED) {
        // Disconnection
        private_window.run("document.getElementById(\"Logs\").value += \"Disconnected.\\n\";");
    }
}

fn private_window_events(e: *webui.Event) void {
    if (e.event_type == .EVENT_CONNECTED) {

        // get the public window URL and port
        const public_win_port = public_window.getPort() catch unreachable;
        const public_win_url: [:0]const u8 = public_window.getUrl() catch return;

        var buf = std.mem.zeroes([1024]u8);
        const js_1 = std.fmt.bufPrintZ(&buf, "document.getElementById('urlSpan1').innerHTML = 'http://localhost:{}';", .{public_win_port}) catch unreachable;
        private_window.run(js_1);
        const js_2 = std.fmt.bufPrintZ(&buf, "document.getElementById('urlSpan2').innerHTML = '{s}';", .{public_win_url}) catch unreachable;
        private_window.run(js_2);
    }
}

pub fn main() !void {
    // Create windows
    private_window = webui.newWindow();
    public_window = webui.newWindow();

    // App
    webui.setTimeout(0); // Wait forever (never timeout)

    // Public Window
    // Make URL accessible from public networks
    public_window.setPublic(true);

    // Bind all events
    _ = try public_window.bind("", public_window_events);

    _ = try public_window.setPort(9090); // Set port for public access

    // Set public window HTML
    try public_window.showBrowser(public_html, .NoBrowser);

    // Main Private Window

    // Run Js
    _ = try private_window.bind("", private_window_events);

    // Bind exit button
    _ = try private_window.bind("Exit", app_exit);

    // Show the window
    _ = try private_window.show(private_html);

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}
