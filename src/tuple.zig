//! Tuple-synthesis helper.
//!
//! Uses the `@Tuple` builtin (available on Zig 0.16+) to construct a tuple
//! type from a function's parameter list. Used by `webui.bind` to build the
//! argument tuple passed to user callbacks.
const std = @import("std");

pub fn fnParamsToTuple(comptime params: []const std.builtin.Type.Fn.Param) type {
    var types: [params.len]type = undefined;
    for (params, 0..) |param, i| {
        types[i] = param.type orelse @compileError("param must have type");
    }
    return @Tuple(&types);
}
