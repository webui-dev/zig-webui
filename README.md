# zig-webui

zig-webui is being rebuilt as a pure Zig WebUI implementation. The core no
longer compiles or links the upstream WebUI C library or CivetWeb.
[Linsang](https://github.com/jinzhongjia/Linsang) provides HTTP and WebSocket
support.

The current phase provides:

- Zig 0.16;
- one `App`, one window, and automatic port selection;
- embedded HTML and a built-in JavaScript bridge;
- JavaScript calls to Zig bindings with return values;
- window and targeted `Call.client` calls to JavaScript with results, errors,
  timeouts, and stale-client detection;
- default-browser launching and deterministic shutdown.

```zig
const std = @import("std");
const webui = @import("webui");

fn hello(call: *webui.Call, _: ?*anyopaque) !void {
    try call.reply("Hello from Zig");
}

pub fn main() !void {
    const gpa = std.heap.page_allocator;
    var threaded = std.Io.Threaded.init(gpa, .{ .async_limit = .unlimited });
    defer threaded.deinit();
    const io = threaded.io();

    var app = webui.App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{
        .html =
        \\<button onclick="webui.call('hello').then(alert)">Call Zig</button>
        \\<script src="/webui.js"></script>
        ,
    });
    try window.bind("hello", hello, null);

    var running = try app.start(io);
    defer running.stop() catch {};
    try window.open(io, &running);

    var result_buffer: [64]u8 = undefined;
    const result = try window.eval(
        io,
        "return 6 * 7",
        &result_buffer,
        .fromSeconds(5),
    );
    switch (result) {
        .value => |value| std.debug.print("JavaScript: {s}\n", .{value}),
        .javascript_error => |message| std.log.err("JavaScript: {s}", .{message}),
    }
    try running.wait();
}
```

```sh
zig build test
zig build
zig build run
```

Multiple windows, directory content, broadcasts, and multiple clients belong
to later phases. See the
[pure Zig refactor plan](docs/PURE_ZIG_REFACTOR.md) for the complete scope and
implementation order.

## License

MIT
