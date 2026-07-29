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
- application-wide default static directories for windows without content;
- optional recursive directory monitoring with per-window browser reloads;
- inline and file-backed per-window favicons;
- runtime content and resource-handler replacement through
  `Window.setContent()`;
- targeted runtime content replacement through `Client.show()`;
- explicit browser connection waiting and timeout through
  `Window.waitForConnection()`;
- window connected/shown state through `Window.isShown()`;
- JavaScript calls to Zig bindings with return values;
- typed integer, float, and boolean call arguments and replies;
- owned one-shot delayed binding replies through `Call.deferReply()`;
- window and targeted `Call.client` calls to JavaScript with results, errors,
  timeouts, and stale-client detection;
- targeted client navigation, close, and raw binary delivery;
- bounded multi-client windows through `WindowOptions.max_clients`;
- bounded concurrent evaluations through
  `WindowOptions.max_pending_evals`;
- bounded delayed replies through `WindowOptions.max_pending_replies`;
- explicit connection, WebSocket message, call, argument, binding, event, and
  script limits through `App.Options.limits`;
- window navigation, close, raw-data, and JavaScript broadcasts with
  per-client results;
- targeted and broadcast fire-and-forget JavaScript through `Client.run` and
  `Window.run`;
- connected, disconnected, click, and intercepted navigation events through
  `Window.onEvent`;
- per-window serial or concurrent binding and event execution through
  `Window.setEventMode()`;
- bounded concurrent handlers through `WindowOptions.max_pending_events`;
- caller-provided internal logging through `App.Options.logger`;
- same-origin WebSocket validation for hosted content and external-page Origin
  validation for `.external_url`;
- optional path-scoped `HttpOnly` cookie authorization through
  `App.Options.use_cookies`;
- loopback-only listening by default and caller-provided TLS for explicit
  public listening;
- general OS URL opening and installed-browser discovery;
- explicit browser launching with custom executable paths and argv;
- per-window browser child identifiers and deterministic process cleanup;
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

`Window.open()` launches the browser and returns immediately. Call
`Window.waitForConnection(io, timeout)` when startup must wait for a browser;
it returns the first connected `Client`. `Window.eval()` uses the same total
timeout for connection waiting and JavaScript execution.

Call `openUrl(gpa, io, url)` to open any non-empty URL with the OS default
handler. `browserExists(gpa, io, browser)` checks an explicit `Browser`, while
`bestBrowser(gpa, io)` returns the first installed browser in the preferred
platform order or `null`. Discovery probes Windows application registration,
standard macOS application bundles, and executable candidates on other
platforms without opening the selected browser.

`Window.openWithBrowser(&running, options)` launches a selected `Browser`
with an optional full executable path and additional argv. Chromium-family
browsers receive an `--app=` URL argument; Firefox receives `-new-window`.
The returned `BrowserProcessId`, also available through
`Window.browserProcessId()`, is a PID on POSIX and a process handle on
Windows. Each window retains at most one launched child; launching another
replaces it, and `Running.stop()` kills and reaps every retained child.

Serve a directory by setting
`.content = .{ .directory = "path/to/public" }`. The path is opened when the
app starts and closed when it stops. Custom resources receive `webui.Request`
and `webui.Response` directly.

Set `App.Options.default_directory` to let windows created without `.content`
inherit one static directory. Explicit window content takes precedence. A
window without either setting returns `error.MissingContent`.

Set `App.Options.folder_monitor_interval` to a positive `std.Io.Duration` to
recursively poll active directory content. A changed tree sends
`location.reload();` to that window's connected clients. Monitoring is
disabled by default and stops with `Running.stop()`.

Use `Window.setIcon(io, data, mime_type)` for in-memory favicon data or
`Window.setIconFile(io, path)` for SVG, PNG, ICO, JPEG, GIF, WebP, or AVIF
files. Embedded HTML receives a relative favicon link automatically.
Directory and custom pages can reference `favicon.ico` relative to the window
capability root.

`Window.setContent(&running, content)` prepares and installs new content, then
navigates every connected client to it and returns the number notified. An
invalid replacement leaves the current content unchanged. If client
notification fails, the prepared replacement remains installed.

`Client.show(&running, content)` installs the same window-wide content but
navigates only the selected client, matching upstream `webui_show_client()`.
Other connected pages are not reloaded; later resource requests use the new
window content.

`Window.onEvent` installs one handler for browser lifecycle, click, and
navigation events. `Event.data` contains the element ID for clicks, the target
URL for navigation, and is empty for connected or disconnected events.
Navigation attempts are intercepted while an event handler is installed; call
`Event.client.navigate` from the handler to continue them.

Handlers run in `.serial` mode by default. `Window.setEventMode(.concurrent)`
changes newly received binding calls and browser events to independent tasks.
Concurrent tasks own their event data, are bounded by
`WindowOptions.max_pending_events`, and are canceled and joined by
`Running.stop()`.

Set `App.Options.logger` and optional `logger_user_data` to receive formatted
internal messages with a `std.log.Level`. The message slice is valid only
during the callback. The callback must be thread-safe when concurrent event
handling is enabled. Without a callback, messages use `std.log`.

`Window.bind("button", ...)` also dispatches clicks from elements with
`id="button"`, including elements added after the bridge loads. DOM click
handlers receive no arguments and their replies are ignored; explicit
`webui.call("button", ...)` remains available.

Binding handlers can transfer an explicit `webui.call()` response beyond the
handler lifetime with `Call.deferReply()`. Complete the owned `PendingReply`
once with `reply()`, `replyInt()`, `replyFloat()`, or `replyBool()`, or call
`deinit()` to abandon it. All pending replies must be completed or abandoned
before `App.deinit()`.

The browser-side `webui` object also provides connection events, runtime
logging, Base64 helpers, navigation control, and native high-contrast media
query detection.

Use `Client.run` or `Window.run` when JavaScript results and errors are not
needed. These methods use the protocol's `JS_QUICK` command and do not consume
pending evaluation slots.

External pages use `.content = .{ .external_url = "http://..." }`.
`Window.url` returns the external page, while `Window.bridgeUrl` returns the
capability-scoped script URL that the caller-owned page must load. The bridge
connects its WebSocket to the script's origin instead of the page's origin,
and the server accepts the external page's Origin for that window.

Non-loopback listening requires both explicit public mode and TLS:

```zig
var app = webui.App.init(gpa, .{
    .address = "0.0.0.0",
    .public = true,
    .use_cookies = true,
    .tls = .{
        .certificate_pem = @embedFile("certificate.pem"),
        .private_key_pem = @embedFile("private-key.pem"),
    },
    .limits = .{
        .max_connections = 128,
        .max_unauthenticated_connections = 16,
        .max_ws_message_size = 1 << 20,
    },
});
```

The certificate and private key are parsed by `App.start()` and released by
`Running.stop()`. zig-webui never generates a self-signed certificate.

See the
[pure Zig refactor plan](docs/PURE_ZIG_REFACTOR.md) for the complete scope and
implementation order.

## License

MIT
