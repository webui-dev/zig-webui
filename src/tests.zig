//! Unit tests for the zig-webui bindings.
//!
//! The tests are split into two groups:
//!
//! 1. Pure-Zig checks that don't touch the C library at all (enum integer
//!    values, error sets, Event layout, comptime helpers, version constants).
//! 2. Smoke tests that exercise C entry points which do *not* spin up a
//!    browser or block on a server (window create/destroy, free-port,
//!    mime-type lookup, base64 encode/decode, malloc/free, config setters).
//!
//! Run with `zig build test`.

const std = @import("std");
const builtin = @import("builtin");
const webui = @import("webui");
const compat_tuple = @import("compat_tuple");

fn memFind(comptime T: type, haystack: []const T, needle: []const T) ?usize {
    if (comptime @hasDecl(std.mem, "find")) return std.mem.find(T, haystack, needle);
    return std.mem.indexOf(T, haystack, needle);
}

fn memFindScalar(comptime T: type, haystack: []const T, needle: T) ?usize {
    if (comptime @hasDecl(std.mem, "findScalar")) return std.mem.findScalar(T, haystack, needle);
    return std.mem.indexOfScalar(T, haystack, needle);
}
// =============================================================================
// Pure-Zig tests (no C calls)
// =============================================================================

test "WEBUI_VERSION matches build.zig.zon" {
    try std.testing.expectEqual(@as(u64, 2), webui.WEBUI_VERSION.major);
    try std.testing.expectEqual(@as(u64, 5), webui.WEBUI_VERSION.minor);
    try std.testing.expectEqual(@as(u64, 0), webui.WEBUI_VERSION.patch);
    try std.testing.expectEqualStrings("beta.4", webui.WEBUI_VERSION.pre.?);
}

test "constants" {
    try std.testing.expectEqual(@as(usize, 65535), webui.WEBUI_MAX_IDS);
    try std.testing.expectEqual(@as(usize, 16), webui.WEBUI_MAX_ARG);
}

test "convenience helpers are exposed" {
    try std.testing.expect(@hasDecl(webui, "runFmt"));
    try std.testing.expect(@hasDecl(webui, "scriptResult"));
    try std.testing.expect(@hasDecl(webui.Event, "runClientFmt"));
    try std.testing.expect(@hasDecl(webui.Event, "scriptClientResult"));
    try std.testing.expect(@hasDecl(webui.Event, "returnFmt"));
    try std.testing.expect(@hasDecl(webui.Event, "getRawSlice"));
    try std.testing.expect(@hasDecl(webui.Event, "getRawSliceAt"));
}

test "Browser enum integer values match C ABI" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(webui.Browser.NoBrowser));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(webui.Browser.AnyBrowser));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(webui.Browser.Chrome));
    try std.testing.expectEqual(@as(usize, 13), @intFromEnum(webui.Browser.Webview));
}

test "Runtime enum integer values match C ABI" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(webui.Runtime.None));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(webui.Runtime.Deno));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(webui.Runtime.NodeJS));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(webui.Runtime.Bun));
}

test "LoggerLevel enum integer values match C ABI" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(webui.LoggerLevel.Debug));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(webui.LoggerLevel.Info));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(webui.LoggerLevel.Error));
}

test "EventKind enum integer values match C ABI" {
    try std.testing.expectEqual(@as(usize, 0), @intFromEnum(webui.EventKind.EVENT_DISCONNECTED));
    try std.testing.expectEqual(@as(usize, 1), @intFromEnum(webui.EventKind.EVENT_CONNECTED));
    try std.testing.expectEqual(@as(usize, 2), @intFromEnum(webui.EventKind.EVENT_MOUSE_CLICK));
    try std.testing.expectEqual(@as(usize, 3), @intFromEnum(webui.EventKind.EVENT_NAVIGATION));
    try std.testing.expectEqual(@as(usize, 4), @intFromEnum(webui.EventKind.EVENT_CALLBACK));
}

test "Config enum starts at 0" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(webui.Config.show_wait_connection));
    try std.testing.expectEqual(@as(c_int, 1), @intFromEnum(webui.Config.ui_event_blocking));
}

test "Event is extern struct with stable layout" {
    try std.testing.expect(@typeInfo(webui.Event) == .@"struct");
    try std.testing.expectEqual(.@"extern", @typeInfo(webui.Event).@"struct".layout);

    // The C side relies on this exact field ordering.
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(webui.Event, "window"));
    const event_type_offset = @offsetOf(webui.Event, "event_type");
    try std.testing.expect(event_type_offset > 0);
    try std.testing.expect(@offsetOf(webui.Event, "element") > event_type_offset);
    try std.testing.expect(@offsetOf(webui.Event, "cookies") > @offsetOf(webui.Event, "element"));
}

test "WebUIError contains expected variants" {
    // Compile-time check: every variant we ship is reachable.
    const want: []const webui.WebUIError = &.{
        webui.WebUIError.GenericError,
        webui.WebUIError.CreateWindowError,
        webui.WebUIError.BindError,
        webui.WebUIError.ShowError,
        webui.WebUIError.ServerError,
        webui.WebUIError.EncodeError,
        webui.WebUIError.DecodeError,
        webui.WebUIError.UrlError,
        webui.WebUIError.ProcessError,
        webui.WebUIError.HWNDError,
        webui.WebUIError.PortError,
        webui.WebUIError.ScriptError,
        webui.WebUIError.AllocateFailed,
    };
    try std.testing.expectEqual(@as(usize, 13), want.len);
}

test "compat_tuple.fnParamsToTuple synthesizes correct tuple" {
    const Type = std.builtin.Type;
    const params = [_]Type.Fn.Param{
        .{ .is_generic = false, .is_noalias = false, .type = i32 },
        .{ .is_generic = false, .is_noalias = false, .type = bool },
        .{ .is_generic = false, .is_noalias = false, .type = f64 },
    };
    const Tup = compat_tuple.fnParamsToTuple(&params);

    const info = @typeInfo(Tup).@"struct";
    try std.testing.expect(info.is_tuple);
    try std.testing.expectEqual(@as(usize, 3), info.fields.len);
    try std.testing.expectEqual(i32, info.fields[0].type);
    try std.testing.expectEqual(bool, info.fields[1].type);
    try std.testing.expectEqual(f64, info.fields[2].type);

    // We can build an instance and read it back.
    var t: Tup = undefined;
    t[0] = -7;
    t[1] = true;
    t[2] = 3.5;
    try std.testing.expectEqual(@as(i32, -7), t[0]);
    try std.testing.expect(t[1]);
    try std.testing.expectEqual(@as(f64, 3.5), t[2]);
}

// =============================================================================
// C-backed smoke tests (no browser, no server)
// =============================================================================

test "newWindow then destroy roundtrip" {
    const win = webui.newWindow();
    defer win.destroy();
    // window_handle is a positive id assigned by the C layer.
    try std.testing.expect(win.window_handle > 0);
    try std.testing.expect(win.window_handle < webui.WEBUI_MAX_IDS);

    // The window was just created; nothing is shown yet.
    try std.testing.expect(!win.isShown());
}

test "newWindowWithId rejects 0 and out-of-range ids" {
    try std.testing.expectError(webui.WebUIError.CreateWindowError, webui.newWindowWithId(0));
    try std.testing.expectError(webui.WebUIError.CreateWindowError, webui.newWindowWithId(webui.WEBUI_MAX_IDS));
    try std.testing.expectError(webui.WebUIError.CreateWindowError, webui.newWindowWithId(webui.WEBUI_MAX_IDS + 100));
}

test "newWindowWithId with explicit id" {
    const id = webui.getNewWindowId();
    try std.testing.expect(id > 0);
    try std.testing.expect(id < webui.WEBUI_MAX_IDS);

    const win = try webui.newWindowWithId(id);
    defer win.destroy();
    try std.testing.expectEqual(id, win.window_handle);
}

test "getNewWindowId returns distinct ids" {
    const a = webui.getNewWindowId();
    const b = webui.getNewWindowId();
    try std.testing.expect(a != b);
    try std.testing.expect(a > 0);
    try std.testing.expect(b > 0);
}

test "getFreePort returns a non-zero port" {
    const port = webui.getFreePort();
    try std.testing.expect(port > 0);
    try std.testing.expect(port < 65536);
}

test "getMimeType resolves common extensions" {
    try std.testing.expectEqualStrings("text/html", webui.getMimeType("index.html"));
    try std.testing.expectEqualStrings("text/css", webui.getMimeType("style.css"));
    // JavaScript MIME type label varies a bit across versions; just check it's
    // a non-empty string that mentions javascript.
    const js_mime = webui.getMimeType("app.js");
    try std.testing.expect(js_mime.len > 0);
    try std.testing.expect(memFind(u8, js_mime, "javascript") != null);
}

test "encode then decode roundtrips" {
    const original: [:0]const u8 = "Hello, WebUI!";
    const encoded = try webui.encode(original);
    defer webui.free(encoded);
    try std.testing.expect(encoded.len > 0);
    // Base64 of ASCII has no NUL bytes embedded.
    try std.testing.expect(memFindScalar(u8, encoded, 0) == null);

    // Build a NUL-terminated copy for the decode call (the C API insists).
    var buf: [128]u8 = undefined;
    @memcpy(buf[0..encoded.len], encoded);
    buf[encoded.len] = 0;
    const encoded_z: [:0]const u8 = buf[0..encoded.len :0];

    const decoded = try webui.decode(encoded_z);
    defer webui.free(decoded);
    try std.testing.expectEqualStrings(original, decoded);
}

test "malloc / free roundtrip" {
    const buf = try webui.malloc(64);
    defer webui.free(buf);
    try std.testing.expectEqual(@as(usize, 64), buf.len);
    // We can write to the buffer without faulting.
    @memset(buf, 0xAB);
    try std.testing.expectEqual(@as(u8, 0xAB), buf[0]);
    try std.testing.expectEqual(@as(u8, 0xAB), buf[63]);
}

test "setTimeout / setConfig / setBrowserFolder do not crash" {
    // Pure setters: the most we can check without driving a real browser is
    // that they execute and return.
    webui.setTimeout(0);
    webui.setConfig(.show_wait_connection, true);
    webui.setConfig(.multi_client, false);
    webui.setBrowserFolder("");
}

test "setDefaultRootFolder accepts a relative path" {
    // Should at least succeed for the current working directory.
    try webui.setDefaultRootFolder(".");
}

test "browserExist for NoBrowser returns false" {
    // The "no browser" pseudo-value is never installed; this gives us a
    // deterministic answer without depending on the test host having Chrome.
    try std.testing.expectEqual(false, webui.browserExist(.NoBrowser));
}

test "clean is callable" {
    // No assertion: just make sure the symbol is wired up and doesn't crash.
    webui.clean();
}

// Suppress "unused" warnings for builtin import on 0.14 paths that don't
// touch it directly.
comptime {
    _ = builtin;
}
