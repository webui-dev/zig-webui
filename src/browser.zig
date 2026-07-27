const std = @import("std");
const builtin = @import("builtin");

pub fn open(gpa: std.mem.Allocator, io: std.Io, url: []const u8) !void {
    const result = switch (builtin.os.tag) {
        .windows => try std.process.run(gpa, io, .{
            .argv = &.{ "explorer.exe", url },
        }),
        .macos => try std.process.run(gpa, io, .{
            .argv = &.{ "open", url },
        }),
        else => try std.process.run(gpa, io, .{
            .argv = &.{ "xdg-open", url },
        }),
    };
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.BrowserOpenFailed,
        else => return error.BrowserOpenFailed,
    }
}
