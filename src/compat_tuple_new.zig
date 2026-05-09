//! Tuple synthesis helper for Zig 0.16+.
//!
//! Zig 0.16 removed `@Type` and introduced `@Tuple` as a dedicated builtin
//! for constructing tuple types. The 0.16 parser rejects `@Type` outright
//! (even in unreachable / unselected branches), so the legacy
//! implementation must live in a sibling file (`compat_tuple_old.zig`)
//! that is never compiled on 0.16.
const std = @import("std");

pub fn fnParamsToTuple(comptime params: []const std.builtin.Type.Fn.Param) type {
    var types: [params.len]type = undefined;
    for (params, 0..) |param, i| {
        types[i] = param.type orelse @compileError("param must have type");
    }
    return @Tuple(&types);
}
