//! WebUI Zig - Minimal Example
const webui = @import("webui");

pub fn main() !void {
    // create a new window
    var nwin = webui.newWindow();

    // show the content
    _ = nwin.show("<html><head><script src=\"/webui.js\"></script></head> Hello World ! </html>");

    // wait the window exit
    webui.wait();
}
