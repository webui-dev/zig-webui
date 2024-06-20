//! Text Editor in Zig using WebUI
const std = @import("std");
const webui = @import("webui");

fn close(_: webui.Event) void {
    std.debug.print("Exit.\n", .{});

    // Close all opened windows
    webui.exit();
}

pub fn main() !void {
    // Create a new window
    var mainW = webui.newWindow();

    // Set the root folder for the UI
    _ = mainW.setRootFolder("ui");

    // Bind HTML elements with the specified ID to C functions
    _ = mainW.bind("close_app", close);

    // Show the window, preferably in a chromium based browser
    if (!mainW.showBrowser("index.html", .ChromiumBased))
        _ = mainW.show("index.html");

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}
