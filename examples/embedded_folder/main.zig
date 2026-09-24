//! Embed a complete directory without reading files at runtime.
const std = @import("std");
const webui = @import("webui");
const Assets = webui.EmbeddedFS(@import("embedded_assets"));

pub fn main() void {
    for (Assets.list()) |path| {
        std.debug.print("{s} ({d} bytes)\n", .{ path, Assets.get(path).?.len });
    }
    std.debug.print("\n{s}", .{Assets.get("css/main.css").?});
    std.debug.print("Missing file: {any}\n", .{Assets.get("missing.txt")});
    // Ready-made HTTP response for `setFileHandler(Assets.response)`.
    std.debug.print("\n{s}", .{Assets.response("/css/main.css").?});
}
