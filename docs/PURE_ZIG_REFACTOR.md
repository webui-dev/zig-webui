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

## Current Rewrite Status

Status snapshot: 2026-07-30, after commit `a5dbde0`.

The external-browser core is now implemented in Zig on top of pinned Linsang.
The legacy wrapper, C API, compatibility files, and examples have been
deleted.

| Area | Status |
|---|---|
| Server and security | HTTP, WebSocket, TLS, loopback/public policy, capabilities, Origin checks, cookies, and protocol limits are implemented. |
| Browser bridge | Bindings, typed arguments and replies, events, deferred replies, JavaScript evaluation, raw data, navigation, and multiple clients are implemented. |
| Content and lifecycle | HTML, directories, custom handlers, external URLs, runtime content replacement, default directories, favicons, directory monitoring, logging, and deterministic shutdown are implemented. |
| Browser integration | Default URL opening, browser discovery, explicit browser selection, custom executables and argv, direct child tracking, replacement, and shutdown cleanup are implemented. |
| Current validation | `zig build test`, native builds, Windows x86_64 builds, macOS aarch64 builds, and Windows/macOS test-module cross-compilation pass. |

Remaining work is limited to browser window controls and geometry, managed
profiles and proxies, a portable parent-process numeric ID, server-side
runtimes, optional native WebViews and handles, and the final parity validation
gates. The coverage ledger below is the authoritative method-level list.

## Original Baseline

| Component | Status |
|---|---|
| Original zig-webui | `webui.zig` was about 1,334 lines and `c.zig` about 1,188 lines; most code forwarded the C API |
| Capability reference | WebUI `2.5.0-beta.4` at `337a183cea0a9c5daee16acb77eed2d5443bbbb0` |
| Upstream WebUI | Its core is the roughly 14,500-line `src/webui.c`, mixing protocol, server, browser, WebView, and process management |
| Browser bridge | About 1,006 lines of TypeScript using the 8-byte WebUI binary header |
| Linsang | Zig 0.16 with HTTP/1.1, WebSocket, static files, TLS, and connection lifecycle support |
| Linsang validation | All 101 tests pass at `3b50417e3ddb7a0651a8dd8b7154f26c4d4e5608` |

[Linsang issue #1](https://github.com/jinzhongjia/Linsang/issues/1) added a
reference-counted `WebSocketPeer`, immediate cross-task sends, safe send/close
races, and synchronous access to the actual `port = 0` address through
`Running.address`.

## Product Boundaries

### Complete capability parity target

- Cover every user-visible capability in upstream WebUI `2.5.0-beta.4` at
  commit `337a183cea0a9c5daee16acb77eed2d5443bbbb0`.
- Use Zig-native ownership, errors, names, and types instead of copying C
  signatures.
- Treat the API coverage ledger as the completion contract. Every entry must
  end as implemented or as an explicit Zig standard-library replacement.

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
- Automatic self-signed certificate generation.

### Remaining capability parity

- WebView2, GTK/WebKit, or WKWebView.
- Deno, Node, or Bun server-side runtimes.
- Browser window controls, geometry, and high-contrast control.
- Browser profiles and proxy configuration.
- A portable parent-process numeric ID accessor.

These do not block the external-browser core, but they are required before
declaring complete upstream capability parity.

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

The rewrite keeps the existing WebUI bridge behavior and 8-byte header so
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

try window.open(io, &running);
try running.wait();
```

Use `window.openWithBrowser(&running, options)` when explicit browser
selection, a custom executable, or additional argv is required.

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
| `window.show(content)` | Set initial content and call `window.open()`; use `window.setContent()` while running. |
| `window.bind()` / `binding()` | `window.bind(name, handler, user_data)` |
| `Event.get*At()` | `Call.string/int/float/bool/bytes(index)` |
| `Event.return*()` | `Call.reply*()` |
| `window.run()` | `Window.eval()` |
| `Event.runClient()` | `Call.client.eval()` |
| `setRootFolder()` | Initial `.directory` content or runtime `Window.setContent()`. |
| `setDefaultRootFolder()` | `App.Options.default_directory` and an omitted window `content`. |
| `setIcon()` / `setIconFile()` | `Window.setIcon()` / `Window.setIconFile()`. |
| Global `setConfig()` | `App.Options` or `Window.Options` |
| `wait()` / `clean()` | `Running.wait()` / `App.deinit()` |
| `malloc/free/memcpy/encode/decode` | Zig allocators and standard library |
| `interface*` | Delete |
| `newWindowWithId()` | Delete; `App` owns IDs |

## Upstream WebUI API Coverage Ledger

This ledger tracks upstream WebUI `2.5.0-beta.4` at commit
`337a183cea0a9c5daee16acb77eed2d5443bbbb0`. Upstream C names are identifiers
for traceability, not a commitment to reproduce the C API shape in Zig.
Coverage is determined only from `src/root.zig` and its reachable pure Zig
modules. Deleted legacy wrapper, test, and example files do not count as
implementations.

### Missing or Partial Backend Capabilities

| Upstream API | Current gap |
|---|---|
| `webui_set_kiosk()`, `webui_focus()`, `webui_minimize()`, `webui_maximize()`, `webui_set_hide()` | Browser window mode and lifecycle controls are not implemented. |
| `webui_set_resizable()`, `webui_set_size()`, `webui_set_minimum_size()`, `webui_set_position()`, `webui_set_center()` | Browser window geometry controls are not implemented. |
| `webui_set_frameless()`, `webui_set_transparent()` | Frameless and transparent browser window modes are not implemented. |
| `webui_set_high_contrast()`, `webui_is_high_contrast()` | High-contrast mode control and detection are not implemented. |
| `webui_set_profile()`, `webui_delete_profile()`, `webui_delete_all_profiles()` | Managed browser profiles are not implemented. |
| `webui_set_proxy()` | Browser proxy configuration is not implemented. |
| `webui_get_parent_process_id()` | A portable parent-process numeric ID accessor is not implemented. |
| `webui_set_runtime()` | Deno, Node.js, and Bun execution for served files is not implemented. |
| `webui_show_wv()`, `webui_set_close_handler_wv()`, `webui_get_hwnd()`, `webui_win32_get_hwnd()` | Native WebView hosting and native window handles are outside the pure Zig browser core. |

### Browser Bridge APIs

The browser-side `webui` object implements `call()`, `isConnected()`,
`setLogging()`, `encode()`, `decode()`, `setEventCallback()`, `event`,
`isHighContrast()`, and `allowNavigation()`. Encoding delegates to `btoa()`
and `atob()`, while high-contrast detection uses native browser media
queries. The upstream bridge's `callCore()` method remains an internal
implementation detail.

### Intentional Zig Replacements

The following upstream methods are covered by the current Zig design and are
not implementation gaps:

| Upstream API | Zig replacement |
|---|---|
| `webui_new_window()`, `webui_new_window_id()`, `webui_get_new_window_id()` | `App.createWindow()` and application-owned IDs. |
| `webui_show()`, `webui_start_server()`, `webui_get_url()` | Initial `Content`, runtime `Window.setContent()`, `App.start()`, `Window.open()`, and `Window.url()`. |
| `webui_show_client()` | `Client.show()` replaces the window content and navigates only the selected client. |
| `webui_is_shown()` | `Window.isShown()` reports whether the window has at least one connected browser client. |
| `webui_open_url()` | `openUrl()` safely passes a non-empty URL as one argument to the platform default opener. |
| `webui_get_best_browser()`, `webui_browser_exist()` | `bestBrowser()` and `browserExists()` discover registered or executable browser candidates through the public `Browser` enum. |
| `webui_show_browser()`, `webui_set_browser_folder()`, `webui_set_custom_parameters()` | `Window.openWithBrowser()` accepts a `BrowserLaunchOptions` value with an explicit browser, optional full executable path, and additional argv. |
| `webui_get_child_process_id()` | `Window.openWithBrowser()` returns the retained direct child's `BrowserProcessId`; `Window.browserProcessId()` retrieves it later. |
| `webui_set_default_root_folder()` | `App.Options.default_directory` supplies directory content to windows created without explicit content. |
| `webui_set_config(folder_monitor)` | `App.Options.folder_monitor_interval` enables portable recursive directory polling and reloads the affected window's connected clients. |
| `webui_set_icon()`, `webui_set_icon_file()` | `Window.setIcon()` copies inline data and MIME type; `Window.setIconFile()` loads a supported image file as the window favicon. |
| `webui_wait()`, `webui_wait_async()` | `Running.wait()` used directly or through `std.Io` concurrency. |
| `webui_close()`, `webui_destroy()`, `webui_exit()`, `webui_clean()` | `Window.close()`, `Running.stop()`, and `App.deinit()`. |
| `webui_set_context()`, `webui_get_context()` | Binding and event-handler `user_data`. |
| `webui_bind()` | `Window.bind()` handles explicit `webui.call()` requests and zero-argument DOM clicks from elements with a matching ID. |
| `webui_get_count()`, `webui_get_size()`, `webui_get_size_at()` | `Call.arguments.len` and `Call.bytes(index).len`. |
| `webui_get_string()`, `webui_get_string_at()`, `webui_get_int()`, `webui_get_int_at()`, `webui_get_float()`, `webui_get_float_at()`, `webui_get_bool()`, `webui_get_bool_at()` | `Call.string()`, `Call.int()`, `Call.float()`, and `Call.boolean()`. |
| `webui_return_string()`, `webui_return_int()`, `webui_return_float()`, `webui_return_bool()` | `Call.reply()`, `Call.replyInt()`, `Call.replyFloat()`, and `Call.replyBool()`. |
| `webui_set_config(asynchronous_response)` | `Call.deferReply()` transfers the response to a bounded, owned, one-shot `PendingReply`. |
| `webui_set_config(ui_event_blocking)`, `webui_set_event_blocking()` | `WindowOptions.event_mode` and `Window.setEventMode()` select serial or bounded concurrent binding and event execution. |
| `webui_set_config(show_wait_connection)`, `webui_set_timeout()` | `Window.open()` remains non-blocking; callers explicitly compose it with `Window.waitForConnection(io, timeout)`. |
| `webui_run()`, `webui_script()` | `Window.run()` and `Window.eval()`. |
| `webui_run_client()`, `webui_script_client()` | `Client.run()` and `Client.eval()`. |
| `webui_close_client()`, `webui_navigate_client()`, `webui_send_raw_client()` | `Client.close()`, `Client.navigate()`, and `Client.sendRaw()`. |
| `webui_navigate()`, `webui_send_raw()` | `Window.navigate()` and `Window.sendRaw()`. |
| `webui_set_config(multi_client)` | `WindowOptions.max_clients`. |
| `webui_set_config(use_cookies)` | `App.Options.use_cookies` adds a per-window, path-scoped `HttpOnly` authorization cookie while retaining capability URLs and protocol authentication. |
| `webui_set_logger()` | `App.Options.logger` and `logger_user_data`; messages use `std.log.Level` and fall back to `std.log` when no callback is set. |
| `webui_set_public()` | `App.Options.public` permits non-loopback listening only with TLS; Origin and explicit connection and protocol limits are enforced. |
| `webui_set_tls_certificate()` | `App.Options.tls` accepts caller-provided PEM certificate and private-key bytes. |
| `webui_set_port()`, `webui_get_port()`, `webui_get_free_port()` | `App.Options.port`, including `0` for automatic selection, and the running window URL. |
| `webui_set_root_folder()`, `webui_set_file_handler()`, `webui_set_file_handler_window()`, `webui_return_http()` | Initial or runtime `.directory` and `.custom` content through `Content`, `Window.setContent()`, and `Response`. |
| `webui_get_mime_type()` | Linsang resource handling. |
| `webui_encode()`, `webui_decode()`, `webui_malloc()`, `webui_free()`, `webui_memcpy()` | Zig standard library and allocators. |
| `webui_get_last_error_number()`, `webui_get_last_error_message()` | Zig error unions. |
| `webui_interface_*()` | Permanently omitted with the C ABI compatibility layer. |

## Capability Parity Implementation Order

Each work package must add its focused unit or integration checks and update
the coverage ledger in the same commit.

### Network trust boundary

- Add explicit loopback and public listening modes.
- Implement caller-provided TLS certificate and private-key configuration.
- Validate WebSocket Origin values.
- Add connection, unauthenticated connection, WebSocket message, binding
  name, call payload, argument, script, and pending-call limits.
- Implement optional cookie authorization without weakening capability URLs.

This completes the behavior represented by `webui_set_public()`,
`webui_set_tls_certificate()`, and `webui_set_config(use_cookies)`.

### Calls, bindings, and browser bridge (complete)

- Implements the complete public bridge surface.
- Preserves string, number, boolean, and `Uint8Array` call arguments.

This completes `webui_bind()`, the remaining typed argument and return
methods, and the public browser bridge surface.

### Handler and event lifecycle (complete)

Implements asynchronous replies, per-window event scheduling, explicit
connection waiting, and caller-provided logging.

### Dynamic content and client state (complete)

This completes `webui_show()`, `webui_show_client()`, `webui_is_shown()`,
the dynamic root and file-handler methods, `webui_set_default_root_folder()`,
`webui_set_icon()`, and `webui_set_icon_file()`.

### Managed browser launch (complete)

Browser discovery, default URL opening, explicit browser selection, custom
executable paths and argv, per-window direct child identifiers, replacement,
and shutdown cleanup are implemented.

This completes the browser discovery, selection, custom-parameter, and direct
child tracking methods in the ledger.

### Browser window controls

- Implement kiosk, focus, minimize, maximize, hidden, resizable, geometry,
  frameless, transparent, and high-contrast controls where the selected
  browser and platform support them.
- Implement managed profiles and proxy configuration.

This completes the window control, profile, and proxy methods in the ledger.

### File monitoring (complete)

Portable recursive directory polling reloads only the clients of a changed
directory window and follows runtime content replacements.

This completes `webui_set_config(folder_monitor)`.

### Server-side runtimes

- Run served JavaScript and TypeScript through explicitly selected Deno,
  Node.js, or Bun executables.
- Keep runtime execution disabled by default and pass commands as argv.

This completes `webui_set_runtime()`.

### Native WebViews

- Keep WebView support in an optional module so the browser core remains pure
  Zig and has no bundled C, C++, or Objective-C implementation.
- Implement WebView2, GTK/WebKit, and WKWebView adapters using system
  frameworks.
- Add close interception and native window-handle access.

This completes `webui_show_wv()`, `webui_set_close_handler_wv()`,
`webui_get_hwnd()`, and `webui_win32_get_hwnd()`. Platform ABI declarations
inside the optional module require a separate design review; the public
zig-webui API remains Zig-native.

### Parity closure

- Give every ledger row an implemented or replacement status.
- Add retained examples for bindings, dynamic content, public TLS, managed
  browsers, runtimes, and WebViews.
- Run protocol fuzzing, browser end-to-end tests, leak checks, and all target
  builds before publishing the breaking release.

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

Continue capability parity:

1. Add typed browser launch controls for kiosk, hidden, high-contrast,
   resizable, size, and position behavior.
2. Add managed browser profiles and proxy configuration.
