//! WebUI Zig - FrameLess Example
//! Note: This example needs to be manually linked to webview_loader when running on Windows
//! Without webview_loader, it will report that the window is not found and exit immediately
const webui = @import("webui");

// we use @embedFile to embed html
const html = @embedFile("index.html");

fn minimize(e: *webui.Event) void {
    const win = e.getWindow();
    win.minimize();
}

fn maximize(e: *webui.Event) void {
    const win = e.getWindow();
    win.maximize();
}

fn close(e: *webui.Event) void {
    const win = e.getWindow();
    win.close();
}

pub fn main() !void {
    // create a new window
    var nwin = webui.newWindow();

    _ = try nwin.bind("minimize", minimize);
    _ = try nwin.bind("maximize", maximize);
    _ = try nwin.bind("close", close);

    nwin.setSize(800, 600);
    nwin.setFrameless(true);
    nwin.setTransparent(true);
    nwin.setResizable(true);
    nwin.setCenter();

    try nwin.showWv(html);

    // wait the window exit
    webui.wait();
}
