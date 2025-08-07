const std = @import("std");
const webui = @import("webui");

pub fn main() !void {
    // Demonstrate error handling throughout the application
    std.debug.print("Starting Error Handling Example\n", .{});

    // Set a timeout for connection (10 seconds)
    webui.setTimeout(10);

    const window = webui.newWindow();
    defer window.destroy();

    // Bind error demonstration functions
    _ = try window.bind("test_show_error", testShowError);
    _ = try window.bind("test_port_error", testPortError);
    _ = try window.bind("test_script_error", testScriptError);
    _ = try window.bind("test_encode_error", testEncodeError);
    _ = try window.bind("test_window_id_error", testWindowIdError);
    _ = try window.bind("get_last_error", getLastErrorInfo);
    _ = try window.bind("test_timeout", testTimeout);

    // Show the main window
    window.show("index.html") catch |err| {
        std.debug.print("Failed to show window: {}\n", .{err});
        const error_info = webui.getLastError();
        std.debug.print("WebUI Error #{}: {s}\n", .{ error_info.num, error_info.msg });
        return err;
    };

    webui.wait();
}

fn testShowError(e: *webui.Event) void {
    const window = e.getWindow();

    // Try to show with invalid content (simulate error)
    window.show("nonexistent_file_that_does_not_exist.html") catch |err| {
        const error_info = webui.getLastError();

        var buffer: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        writer.print("Show Error: {}\nWebUI Error #{}: {s}", .{ err, error_info.num, error_info.msg }) catch {};

        const written = fbs.getWritten();
        var null_terminated: [513]u8 = undefined;
        @memcpy(null_terminated[0..written.len], written);
        null_terminated[written.len] = 0;

        e.returnString(null_terminated[0..written.len :0]);
        return;
    };

    e.returnString("No error occurred");
}

fn testPortError(e: *webui.Event) void {
    const window = e.getWindow();

    // Try to set an invalid port (port 1 is usually restricted)
    window.setPort(1) catch |err| {
        const error_info = webui.getLastError();

        var buffer: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        writer.print("Port Error: {}\nWebUI Error #{}: {s}", .{ err, error_info.num, error_info.msg }) catch {};

        const written = fbs.getWritten();
        var null_terminated: [513]u8 = undefined;
        @memcpy(null_terminated[0..written.len], written);
        null_terminated[written.len] = 0;

        e.returnString(null_terminated[0..written.len :0]);
        return;
    };

    e.returnString("Port set successfully (unexpected)");
}

fn testScriptError(e: *webui.Event) void {
    const window = e.getWindow();

    // Try to execute invalid JavaScript
    var result_buffer: [256]u8 = undefined;
    window.script("this_is_invalid_javascript()", 1000, &result_buffer) catch |err| {
        const error_info = webui.getLastError();

        var buffer: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        writer.print("Script Error: {}\nWebUI Error #{}: {s}", .{ err, error_info.num, error_info.msg }) catch {};

        const written = fbs.getWritten();
        var null_terminated: [513]u8 = undefined;
        @memcpy(null_terminated[0..written.len], written);
        null_terminated[written.len] = 0;

        e.returnString(null_terminated[0..written.len :0]);
        return;
    };

    e.returnString("Script executed (unexpected)");
}

fn testEncodeError(e: *webui.Event) void {
    // Test encoding with proper error handling
    const test_string = "Test encoding string";

    const encoded = webui.encode(test_string) catch |err| {
        var buffer: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        writer.print("Encode Error: {}", .{err}) catch {};

        const written = fbs.getWritten();
        var null_terminated: [257]u8 = undefined;
        @memcpy(null_terminated[0..written.len], written);
        null_terminated[written.len] = 0;

        e.returnString(null_terminated[0..written.len :0]);
        return;
    };
    defer webui.free(encoded);

    // Try to decode invalid base64
    const invalid_base64 = "This is not valid base64!!!";
    const decoded = webui.decode(invalid_base64) catch |err| {
        var buffer: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        writer.print("Decode Error: {} (Expected for invalid base64)", .{err}) catch {};

        const written = fbs.getWritten();
        var null_terminated: [257]u8 = undefined;
        @memcpy(null_terminated[0..written.len], written);
        null_terminated[written.len] = 0;

        e.returnString(null_terminated[0..written.len :0]);
        return;
    };
    defer webui.free(decoded);

    e.returnString("No errors occurred");
}

fn testWindowIdError(e: *webui.Event) void {
    // Try to create window with invalid ID
    const invalid_window = webui.newWindowWithId(0) catch |err| {
        var buffer: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        writer.print("Window ID Error: {} (ID 0 is invalid)", .{err}) catch {};

        const written = fbs.getWritten();
        var null_terminated: [257]u8 = undefined;
        @memcpy(null_terminated[0..written.len], written);
        null_terminated[written.len] = 0;

        e.returnString(null_terminated[0..written.len :0]);
        return;
    };

    invalid_window.destroy();
    e.returnString("Window created (unexpected)");
}

fn getLastErrorInfo(e: *webui.Event) void {
    const error_info = webui.getLastError();

    var buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    writer.print("Last Error Information:\nError Number: {}\nError Message: {s}", .{ error_info.num, error_info.msg }) catch {};

    const written = fbs.getWritten();
    var null_terminated: [513]u8 = undefined;
    @memcpy(null_terminated[0..written.len], written);
    null_terminated[written.len] = 0;

    e.returnString(null_terminated[0..written.len :0]);
}

fn testTimeout(e: *webui.Event) void {
    // Demonstrate timeout configuration
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    writer.print("Current timeout is set to 10 seconds.\nSet to 0 for infinite wait.", .{}) catch {};

    const written = fbs.getWritten();
    var null_terminated: [257]u8 = undefined;
    @memcpy(null_terminated[0..written.len], written);
    null_terminated[written.len] = 0;

    e.returnString(null_terminated[0..written.len :0]);
}

