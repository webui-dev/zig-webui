//! Tuple synthesis helper for Zig 0.14 / 0.15.
//!
//! Uses `@Type(.{ .@"struct" = ... })` which was removed in 0.16. This file
//! must NOT be parsed on 0.16 — `build.zig` selects the right sibling
//! (`compat_tuple_new.zig`) for the active Zig version.
const std = @import("std");

pub fn fnParamsToTuple(comptime params: []const std.builtin.Type.Fn.Param) type {
    const Type = std.builtin.Type;
    const fields: [params.len]Type.StructField = blk: {
        var res: [params.len]Type.StructField = undefined;

        for (params, 0..params.len) |param, i| {
            res[i] = Type.StructField{
                .type = param.type.?,
                .alignment = @alignOf(param.type.?),
                .default_value_ptr = null,
                .is_comptime = false,
                .name = std.fmt.comptimePrint("{}", .{i}),
            };
        }
        break :blk res;
    };
    return @Type(.{
        .@"struct" = std.builtin.Type.Struct{
            .layout = .auto,
            .is_tuple = true,
            .decls = &.{},
            .fields = &fields,
        },
    });
}
