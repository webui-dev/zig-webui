const std = @import("std");
const webui = @import("webui");

const html =
    \\<!doctype html>
    \\<html>
    \\<body>
    \\  <button id="hello">Call Zig</button>
    \\  <output id="result"></output>
    \\  <script src="/webui.js"></script>
    \\  <script>
    \\    hello.onclick = async () => result.value = await webui.call("hello", "Zig");
    \\  </script>
    \\</body>
    \\</html>
;

fn hello(call: *webui.Call, _: ?*anyopaque) !void {
    var buffer: [128]u8 = undefined;
    try call.reply(try std.fmt.bufPrint(
        &buffer,
        "Hello, {s}!",
        .{try call.string(0)},
    ));
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var threaded = std.Io.Threaded.init(gpa, .{ .async_limit = .unlimited });
    defer threaded.deinit();
    const io = threaded.io();

    var app = webui.App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{ .html = html });
    try window.bind("hello", hello, null);

    var running = try app.start(io);
    defer running.stop() catch {};

    const url = try running.url(gpa);
    defer gpa.free(url);
    std.debug.print("WebUI: {s}\n", .{url});

    window.open(io, &running) catch |err| {
        std.log.warn("could not open the default browser: {}", .{err});
    };
    try running.wait();
}
