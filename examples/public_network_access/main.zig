//! Public Network Access Example
const std = @import("std");
const webui = @import("webui");

// embed the html
const private_html = @embedFile("private.html");
const public_html = @embedFile("public.html");

// two windows
var private_window: webui = undefined;
var public_window: webui = undefined;

fn app_exit(_: webui.Event) void {
    webui.exit();
}

fn public_window_events(e: webui.Event) void {
    if (e.event_type == .EVENT_CONNECTED) {
        // New connection
        private_window.run("document.getElementById(\"Logs\").value += \"New connection.\\n\";");
    } else if (e.event_type == .EVENT_DISCONNECTED) {
        // Disconnection
        private_window.run("document.getElementById(\"Logs\").value += \"Disconnected.\\n\";");
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
    _ = public_window.bind("", public_window_events);

    // Set public window HTML
    _ = public_window.showBrowser(public_html, .NoBrowser);

    // Get URL of public window
    const public_win_url = public_window.getUrl();

    // Main Private Window

    // Bind exit button
    _ = private_window.bind("Exit", app_exit);

    // Show the window
    _ = private_window.show(private_html);

    // Set URL in the UI
    var javascript = std.mem.zeroes([1024]u8);
    const js = std.fmt.bufPrint(&javascript, "document.getElementById('urlSpan').innerHTML = '{s}';", .{public_win_url}) catch unreachable;

    // convert to a Sentinel-Terminated slice
    const content: [:0]const u8 = javascript[0..js.len :0];

    // run script
    private_window.run(content);

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}
