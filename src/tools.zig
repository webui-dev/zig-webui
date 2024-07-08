const std = @import("std");

const comptimePrint = std.fmt.comptimePrint;

/// Get the string length.
/// This function is exposed to process the string returned by c
pub fn str_len(str: anytype) usize {
    const t = @TypeOf(str);
    switch (t) {
        [*c]u8, [*c]const u8, [*:0]u8, [*:0]const u8 => {
            return std.mem.len(str);
        },
        else => {
            const err_msg = comptimePrint("type of str ({}) should be [*c]u8 or [*c]const u8", .{t});
            @compileError(err_msg);
        },
    }
}
