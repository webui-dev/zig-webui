const std = @import("std");
const webui = @import("webui");

const private_html = @embedFile("private.html");
const public_html = @embedFile("public.html");

var private_window: webui = undefined;
var public_window: webui = undefined;

fn app_exit(_: webui.Event) void {
    webui.exit();
}

fn public_window_events(e: webui.Event) void {
    if (e.event_type == .EVENT_CONNECTED) {
        private_window.run("document.getElementById(\"Logs\").value += \"New connection.\\n\";");
    } else if (e.event_type == .EVENT_DISCONNECTED) {
        private_window.run("document.getElementById(\"Logs\").value += \"Disconnected.\\n\";");
    }
}

pub fn main() !void {
    private_window = webui.newWindow();
    public_window = webui.newWindow();

    webui.setTimeout(0);

    public_window.setPublic(true);

    _ = public_window.bind("", public_window_events);

    _ = public_window.showBrowser(public_html, .NoBrowser);

    const public_win_url = public_window.getUrl();

    _ = private_window.bind("Exit", app_exit);

    _ = private_window.show(private_html);

    var javascript: [1024]u8 = std.mem.zeroes([1024]u8);

    const js = std.fmt.bufPrint(&javascript, "document.getElementById('urlSpan').innerHTML = '{s}';", .{public_win_url}) catch unreachable;

    // convert to a Sentinel-Terminated slice
    const content: [:0]const u8 = javascript[0..js.len :0];

    private_window.run(content);

    webui.wait();

    webui.clean();
}
