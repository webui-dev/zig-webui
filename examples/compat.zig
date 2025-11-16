//! Compatibility layer for Zig 0.15 and 0.16
const std = @import("std");
const builtin = @import("builtin");

// Check Zig version
const zig_version = builtin.zig_version;
const is_zig_0_16_or_later = zig_version.minor >= 16;

// C time function fallback for Zig 0.16
extern "c" fn time(tloc: ?*i64) i64;

/// Get current Unix timestamp in seconds
pub fn timestamp() i64 {
    if (is_zig_0_16_or_later) {
        // Zig 0.16: use C time function
        return time(null);
    } else {
        // Zig 0.15 and earlier
        return std.time.timestamp();
    }
}

/// Get current timestamp in nanoseconds
pub fn nanoTimestamp() i128 {
    if (is_zig_0_16_or_later) {
        // Zig 0.16: approximate with seconds precision
        return @as(i128, time(null)) * 1_000_000_000;
    } else {
        // Zig 0.15 and earlier
        return std.time.nanoTimestamp();
    }
}

/// Create a fixed buffer stream compatible with both Zig 0.15 and 0.16
/// Returns the appropriate FixedBufferStream type for the Zig version
pub fn fixedBufferStream(buffer: []u8) FixedBufferStream {
    if (comptime is_zig_0_16_or_later) {
        // Zig 0.16: construct FixedBufferStream directly
        return .{ .buffer = buffer, .pos = 0 };
    } else {
        // Zig 0.15 and earlier: use helper function
        return std.io.fixedBufferStream(buffer);
    }
}

/// Type alias for FixedBufferStream that works in both versions
pub const FixedBufferStream = if (is_zig_0_16_or_later)
blk: {
    // Zig 0.16: Define our own FixedBufferStream with custom Writer
    break :blk struct {
        buffer: []u8,
        pos: usize = 0,

        const Self = @This();

        // Custom Writer implementation for Zig 0.16
        pub const Writer = struct {
            context: *Self,

            pub fn writeAll(self: Writer, bytes: []const u8) error{NoSpaceLeft}!void {
                const written = try self.context.write(bytes);
                if (written != bytes.len) return error.NoSpaceLeft;
            }

            pub fn print(self: Writer, comptime format: []const u8, args: anytype) error{NoSpaceLeft}!void {
                const context = self.context;
                const remaining = context.buffer[context.pos..];
                const written_slice = std.fmt.bufPrint(remaining, format, args) catch return error.NoSpaceLeft;
                context.pos += written_slice.len;
            }
        };

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        fn write(self: *Self, bytes: []const u8) error{NoSpaceLeft}!usize {
            if (self.pos + bytes.len > self.buffer.len) {
                return error.NoSpaceLeft;
            }
            @memcpy(self.buffer[self.pos..][0..bytes.len], bytes);
            self.pos += bytes.len;
            return bytes.len;
        }

        pub fn getWritten(self: Self) []const u8 {
            return self.buffer[0..self.pos];
        }
    };
} else blk: {
    // Zig 0.15: Use standard library type
    break :blk @TypeOf(std.io.fixedBufferStream(@as([]u8, undefined)));
};
