const std = @import("std");
const webui = @import("webui");

fn close(_: webui.Event) void {
    std.debug.print("Exit.\n", .{});

    webui.exit();
}

pub fn main() !void {
    var mainW = webui.newWindow();

    _ = mainW.setRootFolder("ui");

    _ = mainW.bind("__close-btn", close);

    if (!mainW.showBrowser("index.html", .ChromiumBased)) {
        _ = mainW.show("index.html");
    }

    webui.wait();

    webui.clean();
}
