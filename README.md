# zig-webui

zig-webui is being rebuilt as a pure Zig WebUI implementation. The core no
longer compiles or links the upstream WebUI C library or CivetWeb.
[Linsang](https://github.com/jinzhongjia/Linsang) provides HTTP and WebSocket
support.

The current phase provides:

- Zig 0.16;
- one `App`, multiple isolated windows, and automatic port selection;
- embedded HTML, static directories, custom resources, external URLs, and a
  built-in JavaScript bridge;
- JavaScript calls to Zig bindings with return values;
- window and targeted `Call.client` calls to JavaScript with results, errors,
  timeouts, and stale-client detection;
- targeted client navigation, close, and raw binary delivery;
- bounded multi-client windows through `WindowOptions.max_clients`;
- bounded concurrent evaluations through
  `WindowOptions.max_pending_evals`;
- window navigation, close, raw-data, and JavaScript broadcasts with
  per-client results;
- targeted and broadcast fire-and-forget JavaScript through `Client.run` and
  `Window.run`;
- connected, disconnected, click, and intercepted navigation events through
  `Window.onEvent`;
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
        .content = .{
            .html =
            \\<button onclick="webui.call('hello').then(alert)">Call Zig</button>
            \\<script src="webui.js"></script>
            ,
        },
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

`zig build test` uses Node's built-in test runner for the browser bridge.
Building and using the library does not require Node or npm. `Window.evalAll`
returns owned results; call `deinit` on them after consuming every per-client
outcome.

Serve a directory by setting
`.content = .{ .directory = "path/to/public" }`. The path is opened when the
app starts and closed when it stops. Custom resources receive `webui.Request`
and `webui.Response` directly.

`Window.onEvent` installs one handler for browser lifecycle, click, and
navigation events. `Event.data` contains the element ID for clicks, the target
URL for navigation, and is empty for connected or disconnected events.
Navigation attempts are intercepted while an event handler is installed; call
`Event.client.navigate` from the handler to continue them.

Use `Client.run` or `Window.run` when JavaScript results and errors are not
needed. These methods use the protocol's `JS_QUICK` command and do not consume
pending evaluation slots.

External pages use `.content = .{ .external_url = "http://..." }`.
`Window.url` returns the external page, while `Window.bridgeUrl` returns the
capability-scoped script URL that the caller-owned page must load. The bridge
connects its WebSocket to the script's origin instead of the page's origin.
HTTPS external pages require HTTPS bridge serving, which is part of the TLS
work.

See the
[pure Zig refactor plan](docs/PURE_ZIG_REFACTOR.md) for the complete scope and
implementation order.

## License

MIT
