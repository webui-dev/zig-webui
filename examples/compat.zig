//! Convenience layer over the Zig 0.16 standard library for the examples.
//!
//! Zig 0.16 threads an `std.Io` instance through the filesystem and process
//! APIs and reworked the writer interfaces (Writergate). These helpers wrap
//! that surface so each example stays short and readable. Requires Zig 0.16
//! or later (see `minimum_zig_version` in build.zig.zon).
const std = @import("std");

// C `time` is used instead of `std.time`, whose shape changed in 0.16.
extern "c" fn time(tloc: ?*i64) i64;

/// Get current Unix timestamp in seconds.
pub fn timestamp() i64 {
    return time(null);
}

/// Get current timestamp in nanoseconds (seconds precision).
pub fn nanoTimestamp() i128 {
    return @as(i128, time(null)) * 1_000_000_000;
}

/// Create a fixed buffer stream.
pub fn fixedBufferStream(buffer: []u8) FixedBufferStream {
    return .{ .buffer = buffer, .pos = 0 };
}

/// Minimal fixed-buffer stream with a Writer that matches the 0.16 writer API.
pub const FixedBufferStream = struct {
    buffer: []u8,
    pos: usize = 0,

    const Self = @This();

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

// ===== Allocator compat ======================================================

/// `std.heap.GeneralPurposeAllocator` was renamed to `std.heap.DebugAllocator`
/// in Zig 0.16. Kept under the old name so example code reads the same.
pub const GeneralPurposeAllocator = std.heap.DebugAllocator;

// ===== Filesystem compat =====================================================
//
// `std.fs.cwd()` and the synchronous `std.fs.File` API were removed in 0.16.
// The new API lives under `std.Io.Dir` / `std.Io.File` and threads an `io`
// instance through every call. The helpers below give the examples a small,
// uniform surface that hides this plumbing.

/// Create directories as needed up to (and including) `path`. Equivalent to
/// `mkdir -p` on POSIX.
pub fn makePath(path: []const u8) !void {
    const io = ioInstance();
    try std.Io.Dir.cwd().createDirPath(io, path);
}

/// Create a single directory. Returns an error if `path` already exists.
pub fn makeDir(path: []const u8) !void {
    const io = ioInstance();
    try std.Io.Dir.cwd().createDir(io, path, .default_dir);
}

/// Delete a regular file relative to the current working directory.
pub fn deleteFile(path: []const u8) !void {
    const io = ioInstance();
    try std.Io.Dir.cwd().deleteFile(io, path);
}

/// One-shot "create file and write everything to it" helper.
pub fn writeFile(path: []const u8, content: []const u8) !void {
    const io = ioInstance();
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, content);
}

/// Return true if `path` exists and is a directory (relative to the cwd).
pub fn folderExists(path: []const u8) bool {
    const io = ioInstance();
    var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

/// Write the absolute current working directory into `buffer` and return the
/// written slice.
pub fn cwdPath(buffer: []u8) ![]const u8 {
    const io = ioInstance();
    const len = try std.process.currentPath(io, buffer);
    return buffer[0..len];
}

/// Process-global single-threaded `std.Io` backed by a real allocator.
///
/// The stdlib's `std.Io.Threaded.global_single_threaded` uses a *failing*
/// allocator (`init_single_threaded.allocator = .failing`), so any operation
/// that needs to allocate — notably `std.process.spawn` — fails with
/// `error.OutOfMemory`. This mirrors that single-threaded configuration but
/// swaps in `page_allocator` so allocating operations work.
var io_threaded: std.Io.Threaded = init: {
    var t: std.Io.Threaded = .init_single_threaded;
    t.allocator = std.heap.page_allocator;
    break :init t;
};

/// Get a usable `std.Io` instance. Cheap to call: returns the process-global
/// single-threaded implementation described above.
fn ioInstance() std.Io {
    return io_threaded.io();
}

// ===== Child process compat ==================================================
//
// Zig 0.16 reworked child-process spawning around `std.process.spawn(io,
// options)`. The wrapper below is intentionally narrow — it exposes only what
// the examples need: spawn-with-argv, get the OS pid, and kill.

pub const ChildProcess = struct {
    /// OS-level pid. Optional because 0.16 stores it as `?i32` (the value is
    /// `null` after `kill`/`wait`).
    pid: ?std.process.Child.Id,
    child: std.process.Child,

    /// Spawn a process with the given argv.
    pub fn spawn(argv: []const []const u8) !ChildProcess {
        const io = ioInstance();
        const child = try std.process.spawn(io, .{ .argv = argv });
        return .{ .pid = child.id, .child = child };
    }

    pub fn kill(self: *ChildProcess) !void {
        const io = ioInstance();
        self.child.kill(io);
    }
};
