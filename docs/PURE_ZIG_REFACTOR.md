# zig-webui Pure Zig Refactor Plan

## Goal

Rebuild zig-webui from a Zig wrapper around the WebUI C library into a WebUI
implementation written in Zig:

- Do not compile or link the WebUI C library or CivetWeb.
- Use Linsang for HTTP, WebSocket, and TLS.
- Implement the WebUI protocol, window state, bindings, browser launching, and
  resource routing in Zig.
- Allow breaking Zig API changes without preserving the C ABI shape.
- Support external browsers first. Evaluate native WebViews later as a
  separate module.

Here, pure Zig means the core package and its dependencies contain no bundled
C, C++, or Objective-C implementation. Calling the operating system through
the Zig standard library and launching an installed browser remain in scope.

## Confirmed Baseline

| Component | Status |
|---|---|
| zig-webui | `webui.zig` is about 1,334 lines and `c.zig` about 1,188 lines; most code forwards the C API |
| Current WebUI version | `2.5.0-beta.4`, pinned to `dadf4175d6f2c4060b7a27a32e6e9e64e647116f` |
| Upstream WebUI | Its core is the roughly 14,500-line `src/webui.c`, mixing protocol, server, browser, WebView, and process management |
| Browser bridge | About 1,006 lines of TypeScript using the 8-byte WebUI binary header |
| Linsang | Zig 0.16 with HTTP/1.1, WebSocket, static files, TLS, and connection lifecycle support |
| Linsang validation | All 101 tests pass at `3b50417e3ddb7a0651a8dd8b7154f26c4d4e5608` |
| Current zig-webui validation | `zig build test` passes |

[Linsang issue #1](https://github.com/jinzhongjia/Linsang/issues/1) added a
reference-counted `WebSocketPeer`, immediate cross-task sends, safe send/close
races, and synchronous access to the actual `port = 0` address through
`Running.address`.

## Product Boundaries

### Required for the first release

- One application managing multiple windows.
- Embedded HTML, static directories, and external URLs.
- An automatically served browser bridge.
- Zig bindings with string, number, boolean, and binary arguments.
- JavaScript-to-Zig calls with results.
- Zig-to-JavaScript calls for one client or broadcasts, with results and
  timeouts.
- Connected, disconnected, click, and navigation events.
- Default-browser launching and explicit or automatic ports.
- Loopback listening by default; public listening must be explicit.
- Deterministic shutdown of listeners, clients, windows, and tasks.

### Permanent non-goals

- A C API, `src/c.zig`, extern struct ABI, or interface compatibility APIs.
- Zig 0.14 or 0.15 compatibility. Zig 0.16 is the baseline.

### Explicit first-release non-goals

- WebView2, GTK/WebKit, or WKWebView.
- Deno, Node, or Bun server-side runtimes.
- Automatic reload, proxies, or browser profile management.
- Automatic self-signed certificate generation.
- Complete compatibility with every upstream browser and command-line flag.

Add these only after the core release and only when real use requires them.

## Do Not Translate `webui.c` Line by Line

Zig or Linsang directly replaces these upstream components:

| Upstream implementation | Replacement |
|---|---|
| CivetWeb HTTP/WebSocket/TLS | Linsang |
| malloc/free/ptr_list | Zig allocators and explicit ownership |
| Global `WEBUI_MAX_IDS` arrays | Dynamic window and client state owned by `App` |
| pthread/Win32 mutexes and conditions | `std.Io` tasks and limited synchronization |
| MIME, base64, path, and random helpers | Zig standard library or Linsang |
| One server and port per window | One server per `App`, routed by window capability |
| C ABI events and manual value decoding | Zig `Call` and `Event` types |

Only WebUI-specific behavior needs a Zig implementation:

- bridge packet parsing and encoding;
- token and capability validation;
- window, client, and binding state;
- request and response correlation;
- browser discovery and launching;
- embedded HTML, directory, and custom response routing.

## Protocol Strategy

The first phase keeps the existing WebUI bridge behavior and 8-byte header so
the front end and back end do not change simultaneously:

```text
0      signature  0xDD
1..4   token      little-endian u32
5..6   request id little-endian u16
7      command
8..    payload
```

Support `CHECK_TK`, `CALL_FUNC`, `CLICK`, `JS`, `JS_QUICK`, `NAVIGATION`,
`CLOSE`, and `SEND_RAW` first. Implement `MULTI` only if messages actually
exceed the WebSocket message limit.

`CHECK_TK` carries the 128-bit window capability in its payload. Successful
authentication permanently associates that WebSocket connection with one
window.

Commit the distributable JavaScript bridge as a repository asset. Building
zig-webui must not require Node, npm, or esbuild. Preserve upstream MIT
licensing and attribution. A second protocol version can be considered after
the protocol is stable; it is not a prerequisite for the pure Zig refactor.
The current plan does not include a WASM bridge.

Public network mode cannot rely only on the legacy 32-bit token. The legacy
protocol may remain loopback-only initially. Public mode requires a
high-entropy URL capability, Origin validation, and explicit TLS configuration.

## Proposed API Shape

Center the API on ownership and lifecycle instead of mirroring C handles:

```zig
var app = webui.App.init(gpa, .{});
defer app.deinit();

const window = try app.createWindow(.{
    .content = .{ .html = @embedFile("index.html") },
});
try window.bind("sum", sum, null);

var running = try app.start(io);
defer running.stop() catch {};

try window.open(io, .{ .browser = .default });
try running.wait();
```

Start with one explicit type-erased handler signature:

```zig
fn sum(call: *webui.Call, user_data: ?*anyopaque) !void {
    _ = user_data;
    try call.replyInt(try call.int(0) + try call.int(1));
}
```

The core has only four objects:

- `App`: allocator, Linsang server, window state, and shutdown.
- `Window`: lightweight handle referencing an `App` and window ID.
- `Client`: safely retained connection handle for single-client sends.
- `Call`: arguments, client, and one response for the current invocation.

Automatic adaptation of arbitrary Zig function signatures is a convenience
layer to reconsider only after the core works.

## Minimal Module Layout

```text
src/
  root.zig       public exports
  app.zig        App, Window, Client, routing, bindings, and lifecycle
  protocol.zig   WebUI packet parsing and encoding
  browser.zig    browser discovery and launching through std.process
  bridge.js      browser bridge embedded at build time
```

Keep tests beside their modules. Split `app.zig` only when it develops a clear
independent responsibility.

## Implementation Phases

### 0. Linsang prerequisites (complete)

- `WebSocketPeer` can cross task boundaries with paired `clone` and `deinit`.
- `sendText` and `sendBinary` write immediately and serialize concurrent sends.
- Send/close races return `Closed` or `Canceled` without use-after-free or
  deadlock.
- `Running.address` contains the actual listening port when `start` returns.
- Plaintext and TLS use identical send semantics.

Acceptance: all 101 tests pass at `3b50417`.

### 1. Minimal vertical slice (complete)

- Pin `build.zig.zon` to the Linsang commit.
- Remove the WebUI artifact and `linkLibrary` from `build.zig`.
- Add one `App`, one server, one window, and automatic port selection.
- Serve embedded HTML and the bridge.
- Implement token validation, connection handling, one Zig binding, and its
  response.
- Open the default browser through `std.process`.

Acceptance: the minimal example passed a real Chromium JavaScript-to-Zig call
and clean shutdown; `zig build test` passes; the build graph contains no C.

### 2. Bidirectional calls (complete)

- Implemented single-client `Window.eval` with request IDs.
- Implemented results, JavaScript errors, timeouts, and disconnect cleanup.
- Implemented `Client.run` and broadcast `Window.run` with `JS_QUICK` for
  fire-and-forget JavaScript.
- Implemented stable `Client` handles and targeted `Client.eval`.
- Implemented targeted navigation, close, and raw binary operations.
- Implemented broadcast `Window.evalAll` in the multi-client work.

Acceptance: the call-js-from-zig example passes, and an idle connection
immediately receives Zig-initiated messages. Complete.

### 3. Resources, multiple clients, and events (complete)

- Implemented `.html` and `.directory` content.
- Implemented buffered custom resource handlers using Linsang `Request` and
  `Response` directly.
- Implemented `.external_url`; `Window.bridgeUrl` gives caller-owned pages the
  capability-scoped bridge, which connects back to the script's origin.
- Implemented multiple windows with isolated capability-based routes.
- Implemented a bounded collection of stable `Client` handles; one client is
  the default and `WindowOptions.max_clients` explicitly enables more.
- Implemented a bounded pending-eval table keyed by client and request ID.
- Implemented `Window` navigation, close, raw-data, and evaluation broadcasts.
- Implemented one `Window.onEvent` handler for connected, disconnected, click,
  and intercepted navigation events.

Acceptance: integration tests cover isolated resources, multiple windows,
multiple clients, external bridge routing, lifecycle events, click and
navigation events, and disconnect cleanup. Complete.

### 4. Browser and security completion

- Start with the operating system URL opener.
- Add explicit Chromium or Firefox app-window, kiosk, and sizing flags only
  when required.
- Pass every command as argv without shell interpolation.
- Listen on loopback by default.
- Require a high-entropy capability, Origin validation, and connection,
  message, and call limits for public listening.
- Accept caller-provided TLS certificates; never silently create self-signed
  certificates.

Acceptance: Linux runtime tests and Windows/macOS cross-builds pass; malformed
protocol input never panics.

### 5. Delete the old implementation and publish a breaking release

- Deleted `src/c.zig`, `src/webui.zig`, `src/tests.zig`, both compatibility
  tuple files, and the legacy examples.
- Retain the pure Zig minimal example.
- Document only the new API and lifecycle in the README.
- Publish a new major or alpha release. Naming can be decided then and does not
  block implementation.

## Old API Migration

| Old API | New direction |
|---|---|
| `webui.newWindow()` | `app.createWindow(options)` |
| `window.show(content)` | Set content at creation, then call `window.open()` |
| `window.bind()` / `binding()` | `window.bind(name, handler, user_data)` |
| `Event.get*At()` | `Call.string/int/float/bool/bytes(index)` |
| `Event.return*()` | `Call.reply*()` |
| `window.run()` | `Window.eval()` |
| `Event.runClient()` | `Call.client.eval()` |
| `setRootFolder()` | `.content = .{ .directory = dir }` |
| Global `setConfig()` | `App.Options` or `Window.Options` |
| `wait()` / `clean()` | `Running.wait()` / `App.deinit()` |
| `malloc/free/memcpy/encode/decode` | Zig allocators and standard library |
| `interface*` | Delete |
| `newWindowWithId()` | Delete; `App` owns IDs |

## Upstream WebUI API Coverage Ledger

This ledger tracks upstream WebUI `2.5.0-beta.4` capabilities independently
of the implementation phases. Upstream C names are identifiers for
traceability, not a commitment to reproduce the C API shape in Zig.
Coverage is determined only from `src/root.zig` and its reachable pure Zig
modules. Deleted legacy wrapper, test, and example files do not count as
implementations.

### Missing or Partial Backend Capabilities

| Upstream API | Current gap |
|---|---|
| `webui_bind()` | `Window.bind` supports explicit `webui.call()` calls, but the bridge does not automatically dispatch DOM events from an element with the same ID to that binding. |
| `webui_get_float()`, `webui_get_float_at()` | `Call.float()` is not implemented. |
| `webui_return_float()`, `webui_return_bool()` | `Call.reply()` can encode these values as text, but typed `replyFloat()` and `replyBool()` helpers are not implemented. |
| `webui_show()`, `webui_set_root_folder()`, `webui_set_file_handler()`, `webui_set_file_handler_window()` | Content and resource handling can only be selected when creating a window; replacing them at runtime is not implemented. |
| `webui_show_client()` | `Client` cannot replace the content of only one connected browser. |
| `webui_is_shown()` | There is no window-level connected/shown query. |
| `webui_set_config(asynchronous_response)` | A `Call` response must be completed during the binding handler lifetime. |
| `webui_set_config(show_wait_connection)`, `webui_set_timeout()` | `Window.open()` does not optionally wait for a browser connection. |
| `webui_set_config(ui_event_blocking)`, `webui_set_event_blocking()` | Per-window event scheduling control is not exposed. |
| `webui_set_config(folder_monitor)` | Directory change monitoring and automatic browser reload are not implemented. |
| `webui_set_config(use_cookies)` | Client authorization uses capability URLs; optional cookie-based authorization is not implemented. |
| `webui_set_default_root_folder()` | There is no application-wide default directory content setting. |
| `webui_set_logger()` | There is no caller-provided logging callback. |
| `webui_set_icon()`, `webui_set_icon_file()` | Window icon configuration is not implemented. |
| `webui_open_url()` | The internal OS URL opener is not exposed as a general public API. |
| `webui_get_best_browser()`, `webui_browser_exist()`, `webui_show_browser()`, `webui_set_browser_folder()` | Browser discovery, selection, and custom executable locations are not implemented. |
| `webui_set_custom_parameters()` | Custom browser command-line arguments are not implemented. |
| `webui_set_kiosk()`, `webui_focus()`, `webui_minimize()`, `webui_maximize()`, `webui_set_hide()` | Browser window mode and lifecycle controls are not implemented. |
| `webui_set_resizable()`, `webui_set_size()`, `webui_set_minimum_size()`, `webui_set_position()`, `webui_set_center()` | Browser window geometry controls are not implemented. |
| `webui_set_frameless()`, `webui_set_transparent()` | Frameless and transparent browser window modes are not implemented. |
| `webui_set_high_contrast()`, `webui_is_high_contrast()` | High-contrast mode control and detection are not implemented. |
| `webui_set_profile()`, `webui_delete_profile()`, `webui_delete_all_profiles()` | Managed browser profiles are not implemented. |
| `webui_set_proxy()` | Browser proxy configuration is not implemented. |
| `webui_get_parent_process_id()`, `webui_get_child_process_id()` | Browser process tracking is not implemented. |
| `webui_set_public()` | A guarded public-listening option with Origin validation and explicit limits is not implemented. |
| `webui_set_tls_certificate()` | Caller-provided TLS certificate and private-key configuration is not implemented. |
| `webui_set_runtime()` | Deno, Node.js, and Bun execution for served files is not implemented. |
| `webui_show_wv()`, `webui_set_close_handler_wv()`, `webui_get_hwnd()`, `webui_win32_get_hwnd()` | Native WebView hosting and native window handles are outside the pure Zig browser core. |

### Missing Browser Bridge APIs

The current browser object implements `webui.call()` and
`webui.isConnected()`. These upstream bridge APIs are not implemented:

| Upstream bridge API | Current gap |
|---|---|
| `webui.setLogging()` | Runtime bridge logging control is not exposed. |
| `webui.setEventCallback()` and `webui.event` | Browser-side connected and disconnected callbacks are not exposed. |
| `webui.isHighContrast()` | Browser-side high-contrast detection is not exposed. |
| `webui.allowNavigation()` | Navigation interception cannot be changed by browser JavaScript at runtime. |

`webui.encode()` and `webui.decode()` are intentionally replaced by the
browser's `btoa()` and `atob()` functions. The upstream bridge's
`callCore()` method remains an internal implementation detail.

### Intentional Zig Replacements

The following upstream methods are covered by the current Zig design and are
not implementation gaps:

| Upstream API | Zig replacement |
|---|---|
| `webui_new_window()`, `webui_new_window_id()`, `webui_get_new_window_id()` | `App.createWindow()` and application-owned IDs. |
| `webui_show()`, `webui_start_server()`, `webui_get_url()` | Initial `Content`, `App.start()`, `Window.open()`, and `Window.url()`. Runtime content replacement remains listed above. |
| `webui_wait()`, `webui_wait_async()` | `Running.wait()` used directly or through `std.Io` concurrency. |
| `webui_close()`, `webui_destroy()`, `webui_exit()`, `webui_clean()` | `Window.close()`, `Running.stop()`, and `App.deinit()`. |
| `webui_set_context()`, `webui_get_context()` | Binding and event-handler `user_data`. |
| `webui_get_count()`, `webui_get_size()`, `webui_get_size_at()` | `Call.arguments.len` and `Call.bytes(index).len`. |
| `webui_get_string()`, `webui_get_string_at()`, `webui_get_int()`, `webui_get_int_at()`, `webui_get_bool()`, `webui_get_bool_at()` | `Call.string()`, `Call.int()`, and `Call.boolean()`. |
| `webui_return_string()`, `webui_return_int()` | `Call.reply()` and `Call.replyInt()`. |
| `webui_run()`, `webui_script()` | `Window.run()` and `Window.eval()`. |
| `webui_run_client()`, `webui_script_client()` | `Client.run()` and `Client.eval()`. |
| `webui_close_client()`, `webui_navigate_client()`, `webui_send_raw_client()` | `Client.close()`, `Client.navigate()`, and `Client.sendRaw()`. |
| `webui_navigate()`, `webui_send_raw()` | `Window.navigate()` and `Window.sendRaw()`. |
| `webui_set_config(multi_client)` | `WindowOptions.max_clients`. |
| `webui_set_port()`, `webui_get_port()`, `webui_get_free_port()` | `App.Options.port`, including `0` for automatic selection, and the running window URL. |
| `webui_set_root_folder()`, `webui_set_file_handler()`, `webui_set_file_handler_window()`, `webui_return_http()` | Initial `.directory` or `.custom` content and `Response`. Runtime replacement remains listed above. |
| `webui_get_mime_type()` | Linsang resource handling. |
| `webui_encode()`, `webui_decode()`, `webui_malloc()`, `webui_free()`, `webui_memcpy()` | Zig standard library and allocators. |
| `webui_get_last_error_number()`, `webui_get_last_error_message()` | Zig error unions. |
| `webui_interface_*()` | Permanently omitted with the C ABI compatibility layer. |

## Tests and Completion Criteria

Keep at least one direct test for every non-trivial parser. The final gate is:

```text
zig build test
zig build -Dtarget=x86_64-linux
zig build -Dtarget=aarch64-linux
zig build -Dtarget=x86_64-windows
zig build -Dtarget=x86_64-macos
zig build -Dtarget=aarch64-macos
```

- Protocol tests cover every command, truncated packets, invalid lengths,
  invalid tokens, and unknown commands.
- Node's built-in test runner covers browser bridge command behavior without
  npm dependencies.
- Integration tests cover HTTP content, WebSocket handshake, JavaScript-to-Zig,
  Zig-to-JavaScript, disconnect, and shutdown.
- Fuzz input never panics or reads out of bounds. Messages and pending calls
  have explicit limits.
- `rg 'webui_new|pub extern fn webui_' src` returns no results.
- The build graph contains only the Zig standard library and pinned Linsang,
  with no WebUI or CivetWeb artifact.
- Core integration tests leak no memory under the debug allocator.

## Main Risks

1. **Linsang peer lifecycle:** The required primitive exists. zig-webui must
   pair `clone` and `deinit` and must not retain `*Connection`.
2. **Strict bridge protocol lengths:** The Zig parser must treat WebSocket data
   as untrusted and must not copy C's NUL-scanning behavior.
3. **Cross-platform browser behavior:** Guarantee URL opening first, then add
   platform-specific app-window flags.
4. **WebView is outside the core rewrite:** If required later, separately
   decide whether system framework or C ABI linking is acceptable. It must not
   block the pure Zig browser version.

## Next Implementation Work

Begin phase 4:

1. Validate WebSocket origins and add explicit protocol size limits.
2. Add caller-provided TLS configuration before enabling public listening.
