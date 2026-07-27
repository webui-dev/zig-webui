const std = @import("std");
const webui = @import("webui");

const html =
    \\<!doctype html>
    \\<html>
    \\<body>
    \\  <button id="hello">Call Zig</button>
    \\  <output id="result"></output>
    \\  <script src="webui.js"></script>
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
    const window = try app.createWindow(.{
        .content = .{ .html = html },
    });
    try window.bind("hello", hello, null);

    var running = try app.start(io);
    defer running.stop() catch {};

    const url = try window.url(&running, gpa);
    defer gpa.free(url);
    std.debug.print("WebUI: {s}\n", .{url});

    window.open(io, &running) catch |err| {
        std.log.warn("could not open the default browser: {}", .{err});
    };

    var result_buffer: [64]u8 = undefined;
    const evaluated = window.eval(
        io,
        "document.getElementById('result').value = '42 from JavaScript'; return 6 * 7",
        &result_buffer,
        .fromSeconds(30),
    ) catch |err| {
        std.log.warn("could not call JavaScript: {}", .{err});
        try running.wait();
        return;
    };
    switch (evaluated) {
        .value => |value| std.debug.print("JavaScript: {s}\n", .{value}),
        .javascript_error => |message| std.log.err("JavaScript: {s}", .{message}),
    }
    try running.wait();
}
