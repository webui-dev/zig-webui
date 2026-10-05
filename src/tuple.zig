//! Tuple-synthesis helper.
//!
//! Uses the `@Tuple` builtin (available on Zig 0.16+) to construct a tuple
//! type from a function's parameter types. Used by `webui.bind` to build the
//! argument tuple passed to user callbacks.
//!
//! Takes plain parameter types rather than `std.builtin.Type.Fn.Param`, which
//! Zig 0.17 replaced with the `param_types` slice.

pub fn fnParamsToTuple(comptime param_types: []const ?type) type {
    var types: [param_types.len]type = undefined;
    for (param_types, &types) |param_type, *field_type| {
        field_type.* = param_type orelse @compileError("param must have type");
    }
    return @Tuple(&types);
}
