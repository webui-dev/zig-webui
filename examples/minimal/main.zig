//! WebUI Zig - Minimal Example
const webui = @import("webui");

pub fn main() !void {
    // create a new window
    var nwin = try webui.newWindow();

    // show the content
    try nwin.show("<html><head><script src=\"/webui.js\"></script></head> Hello World ! </html>");

    // wait the window exit
    webui.wait();
}
