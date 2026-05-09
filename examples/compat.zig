//! Compatibility layer for Zig 0.14 / 0.15 / 0.16.
//!
//! Several stdlib APIs the examples rely on were renamed or removed in
//! Zig 0.16 (Writergate, `std.fs` -> `std.Io.Dir`, `GeneralPurposeAllocator`
//! -> `DebugAllocator`, etc). This module hides the version differences
//! so each example can stay short and readable.
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
pub const FixedBufferStream = if (is_zig_0_16_or_later) blk: {
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

// ===== Allocator compat ======================================================

/// `std.heap.GeneralPurposeAllocator` was renamed to `std.heap.DebugAllocator`
/// in Zig 0.16. Use this alias to write code that works on all supported
/// versions.
pub const GeneralPurposeAllocator = if (is_zig_0_16_or_later)
    std.heap.DebugAllocator
else
    std.heap.GeneralPurposeAllocator;

// ===== Filesystem compat =====================================================
//
// `std.fs.cwd()` and the synchronous `std.fs.File` API were removed in 0.16.
// The new API lives under `std.Io.Dir` / `std.Io.File` and threads an `io`
// instance through every call. The helpers below give the examples a small,
// uniform surface that hides this difference.

/// Create directories as needed up to (and including) `path`. Equivalent to
/// `mkdir -p` on POSIX.
pub fn makePath(path: []const u8) !void {
    if (comptime is_zig_0_16_or_later) {
        // Zig 0.16 renamed `makePath` to `createDirPath`.
        const io = ioInstance();
        try std.Io.Dir.cwd().createDirPath(io, path);
    } else {
        try std.fs.cwd().makePath(path);
    }
}

/// Create a single directory. Returns an error if `path` already exists.
pub fn makeDir(path: []const u8) !void {
    if (comptime is_zig_0_16_or_later) {
        // Zig 0.16 renamed `makeDir` to `createDir`; pass the platform default
        // permissions so callers don't need to know the new shape.
        const io = ioInstance();
        try std.Io.Dir.cwd().createDir(io, path, .default_dir);
    } else {
        try std.fs.cwd().makeDir(path);
    }
}

/// Delete a regular file relative to the current working directory.
pub fn deleteFile(path: []const u8) !void {
    if (comptime is_zig_0_16_or_later) {
        const io = ioInstance();
        try std.Io.Dir.cwd().deleteFile(io, path);
    } else {
        try std.fs.cwd().deleteFile(path);
    }
}

/// One-shot "create file and write everything to it" helper. Hides the
/// reader/writer plumbing differences between 0.15 and 0.16.
pub fn writeFile(path: []const u8, content: []const u8) !void {
    if (comptime is_zig_0_16_or_later) {
        const io = ioInstance();
        var file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, content);
    } else {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(content);
    }
}

/// Get a usable `std.Io` instance on 0.16. Cheap to call: returns the
/// process-global single-threaded implementation.
fn ioInstance() std.Io {
    if (comptime !is_zig_0_16_or_later) @compileError("ioInstance is 0.16+ only");
    return std.Io.Threaded.global_single_threaded.io();
}

// ===== Child process compat ==================================================
//
// Zig 0.16 removed `std.process.Child.init(argv, allocator)` and reworked
// child-process spawning around `std.process.spawn(io, options)`. The wrapper
// below is intentionally narrow — it exposes only what the examples need:
// spawn-with-argv, get the OS pid, and kill.

pub const ChildProcess = struct {
    /// OS-level pid. Optional because 0.16 stores it as `?i32` (the value is
    /// `null` after `kill`/`wait`); on 0.14/0.15 it is always populated.
    pid: ?std.process.Child.Id,
    child: std.process.Child,

    /// Spawn a process with the given argv. `allocator` is used for argv
    /// translation on 0.14/0.15; ignored on 0.16 (which routes through Io).
    pub fn spawn(argv: []const []const u8, allocator: std.mem.Allocator) !ChildProcess {
        if (comptime is_zig_0_16_or_later) {
            const io = ioInstance();
            const child = try std.process.spawn(io, .{ .argv = argv });
            return .{ .pid = child.id, .child = child };
        } else {
            // The 0.14/0.15 Child.init signature requires an allocator; suppress
            // the "unused parameter" warning by referencing it explicitly here.
            var child = std.process.Child.init(argv, allocator);
            try child.spawn();
            return .{ .pid = child.id, .child = child };
        }
    }

    pub fn kill(self: *ChildProcess) !void {
        if (comptime is_zig_0_16_or_later) {
            const io = ioInstance();
            self.child.kill(io);
        } else {
            _ = try self.child.kill();
        }
    }
};
