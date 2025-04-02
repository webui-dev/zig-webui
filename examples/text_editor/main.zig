//! Text Editor in Zig using WebUI
const std = @import("std");
const webui = @import("webui");

fn close(_: *webui.Event) void {
    std.debug.print("Exit.\n", .{});

    // Close all opened windows
    webui.exit();
}

pub fn main() !void {
    // Create a new window
    var mainW = try webui.newWindow();

    // Set the root folder for the UI
    try mainW.setRootFolder("ui");

    // Bind HTML elements with the specified ID to C functions
    _ = try mainW.bind("close_app", close);

    // Show the window, this will select the best browser to show
    // and you can use showBrowser to select which browser will be used
    try mainW.show("index.html");

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}
