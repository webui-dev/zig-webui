const webui = @import("webui");

pub fn main() !void {
    var nwin = webui.newWindow();
    _ = nwin.show("<html><head><script src=\"webui.js\"></script></head> Hello World ! </html>");
    webui.wait();
}
