const std = @import("std");
const builtin = @import("builtin");
const build_11 = @import("build_11.zig").build_11;
const build_12 = @import("build_12.zig").build_12;

const Build = std.Build;

const min_zig_string = "0.11.0";

const current_zig = builtin.zig_version;

// NOTE: we should note that when enable tls support we cannot compile with musl

comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
}

pub fn build(b: *Build) void {
    if (current_zig.minor == 11) {
        build_11(b);
    } else if (current_zig.minor == 12) {
        build_12(b);
    }
}
