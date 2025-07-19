//! WebUI Zig - Comprehensive Feature Showcase
//! This example demonstrates multiple WebUI features working together
const std = @import("std");
const webui = @import("webui");

const html = @embedFile("index.html");

var allocator = std.heap.page_allocator;

// Settings storage
var settings_map: std.HashMap([]const u8, []const u8, std.hash_map.StringContext, 80) = undefined;

// Application state
const AppState = struct {
    users_online: u32 = 0,
    messages_sent: u32 = 0,
    files_uploaded: u32 = 0,

    fn init() AppState {
        return AppState{};
    }
};

// Track unique users
var online_users: std.HashMap([]const u8, bool, std.hash_map.StringContext, 80) = undefined;

var app_state: AppState = undefined;

pub fn main() !void {
    // Initialize settings storage
    settings_map = std.HashMap([]const u8, []const u8, std.hash_map.StringContext, 80).init(allocator);
    defer {
        // Clean up all allocated setting keys and values
        var iterator = settings_map.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        settings_map.deinit();
    }

    // Initialize online users tracking
    online_users = std.HashMap([]const u8, bool, std.hash_map.StringContext, 80).init(allocator);
    defer {
        // Clean up all allocated user keys
        var user_iterator = online_users.iterator();
        while (user_iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        online_users.deinit();
    }

    app_state = AppState.init();
    // Configure WebUI
    webui.setConfig(.multi_client, true);
    webui.setConfig(.folder_monitor, true);
    webui.setTimeout(0); // No timeout

    // Create main window
    var main_window = webui.newWindow();

    // Configure window
    main_window.setSize(1200, 800);
    main_window.setCenter();
    main_window.setPublic(true);
    main_window.setIcon("<svg>...</svg>", "image/svg+xml");

    // Set up file handling
    try main_window.setRootFolder("public");
    main_window.setFileHandler(customFileHandler);

    // Bind comprehensive functions
    _ = try main_window.binding("get_app_status", getAppStatus);
    _ = try main_window.binding("user_action", userAction);
    _ = try main_window.binding("send_notification", sendNotification);
    _ = try main_window.binding("process_data", processData);
    _ = try main_window.binding("execute_command", executeCommand);
    _ = try main_window.binding("get_system_info", getSystemInfo);
    _ = try main_window.binding("test_performance", testPerformance);
    _ = try main_window.binding("manage_settings", manageSettings);
    _ = try main_window.binding("upload_file", uploadFile);

    // Set runtime for enhanced JavaScript support
    main_window.setRuntime(.NodeJS);

    // Create public directory
    std.fs.cwd().makeDir("examples/comprehensive/public") catch {};

    // Show window
    try main_window.show(html);

    std.debug.print("Comprehensive WebUI showcase started\n", .{});
    std.debug.print("Port: {}\n", .{main_window.getPort() catch 0});
    std.debug.print("URL: {s}\n", .{main_window.getUrl() catch "unknown"});

    // Wait for window to close
    webui.wait();

    // Clean up
    webui.clean();
}

fn customFileHandler(filename: []const u8) ?[]const u8 {
    // Handle API endpoints
    if (std.mem.startsWith(u8, filename, "/api/")) {
        return handleApiRequest(filename);
    }

    // Handle static files
    if (std.mem.eql(u8, filename, "/status")) {
        const status_html =
            \\HTTP/1.1 200 OK
            \\Content-Type: text/html
            \\
            \\<html><body><h1>WebUI Status</h1><p>Server is running!</p></body></html>
        ;
        return status_html;
    }

    return null; // Let default handler take over
}

fn handleApiRequest(path: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, path, "/api/stats")) {
        var buffer: [512]u8 = undefined;

        const json = std.fmt.bufPrint(buffer[0..],
            \\HTTP/1.1 200 OK
            \\Content-Type: application/json
            \\Access-Control-Allow-Origin: *
            \\
            \\{{"users":{}, "messages":{}, "files":{}}}
        , .{ app_state.users_online, app_state.messages_sent, app_state.files_uploaded }) catch return null;

        // Allocate persistent memory for response
        const response = allocator.dupe(u8, json) catch return null;
        return response;
    }

    return null;
}

fn getAppStatus(e: *webui.Event) void {
    const win = e.getWindow();
    const port = win.getPort() catch 0;
    const url = win.getUrl() catch "unknown";

    var buffer: [1024]u8 = undefined;
    const json = std.fmt.bufPrintZ(buffer[0..],
        \\{{"status":"running","users":{},"messages":{},"files":{},"port":{},"url":"{s}","clientId":{},"timestamp":{}}}
    , .{ app_state.users_online, app_state.messages_sent, app_state.files_uploaded, port, url, e.client_id, std.time.timestamp() }) catch "{\"error\":\"format_error\"}";

    std.debug.print("App Status - Users: {}, Messages: {}, Files: {}\n", .{ app_state.users_online, app_state.messages_sent, app_state.files_uploaded });

    e.returnString(json);
}

fn userAction(e: *webui.Event, action: [:0]const u8, data: [:0]const u8) void {
    std.debug.print("User action: {s} with data: {s}\n", .{ action, data });

    var response: [512]u8 = undefined;
    var result: [:0]const u8 = "";

    if (std.mem.eql(u8, action, "login")) {
        // Check if user is already online
        if (online_users.contains(data)) {
            result = std.fmt.bufPrintZ(response[0..], "User '{s}' is already online. Online users: {}", .{ data, app_state.users_online }) catch "Error";
        } else {
            // Add new user
            const username_copy = allocator.dupe(u8, data) catch {
                result = "Error: Memory allocation failed";
                e.returnString(result);
                return;
            };
            online_users.put(username_copy, true) catch {
                allocator.free(username_copy);
                result = "Error: Failed to track user";
                e.returnString(result);
                return;
            };
            app_state.users_online += 1;
            result = std.fmt.bufPrintZ(response[0..], "User '{s}' logged in. Online users: {}", .{ data, app_state.users_online }) catch "Error";
        }
    } else if (std.mem.eql(u8, action, "logout")) {
        // Check if user is online
        if (online_users.fetchRemove(data)) |kv| {
            allocator.free(kv.key);
            if (app_state.users_online > 0) app_state.users_online -= 1;
            result = std.fmt.bufPrintZ(response[0..], "User '{s}' logged out. Online users: {}", .{ data, app_state.users_online }) catch "Error";
        } else {
            result = std.fmt.bufPrintZ(response[0..], "User '{s}' was not online. Online users: {}", .{ data, app_state.users_online }) catch "Error";
        }
    } else if (std.mem.eql(u8, action, "message")) {
        app_state.messages_sent += 1;
        result = std.fmt.bufPrintZ(response[0..], "Message sent. Total messages: {}", .{app_state.messages_sent}) catch "Error";
    } else if (std.mem.eql(u8, action, "upload")) {
        // For simulation purposes, just acknowledge the upload request
        const filename = if (data.len > 0) data else "demo_file.txt";
        result = std.fmt.bufPrintZ(response[0..], "Upload request received for '{s}'. Use the file input for actual upload.", .{filename}) catch "Error";
    } else {
        result = "Unknown action";
    }

    e.returnString(result);
}

fn sendNotification(e: *webui.Event, message: [:0]const u8, level: [:0]const u8) void {
    const win = e.getWindow();

    // Send notification to all clients
    var js_code: [512]u8 = undefined;
    const script = std.fmt.bufPrintZ(js_code[0..], "showNotification('{s}', '{s}');", .{ message, level }) catch return;

    win.run(script);

    e.returnString("Notification sent to all clients");
    std.debug.print("Notification sent: {s} ({s})\n", .{ message, level });
}

fn processData(e: *webui.Event, operation: [:0]const u8, input_data: [:0]const u8) void {
    std.debug.print("Processing data: {s} on {s}\n", .{ operation, input_data });

    var result: [1024]u8 = undefined;
    var output: [:0]const u8 = "";

    if (std.mem.eql(u8, operation, "reverse")) {
        // Reverse string
        var reversed: [512]u8 = undefined;
        var i: usize = 0;
        while (i < input_data.len and i < 512) : (i += 1) {
            reversed[i] = input_data[input_data.len - 1 - i];
        }
        output = std.fmt.bufPrintZ(result[0..], "Reversed: {s}", .{reversed[0..i]}) catch "Error";
    } else if (std.mem.eql(u8, operation, "uppercase")) {
        // Convert to uppercase
        var upper: [512]u8 = undefined;
        for (input_data, 0..) |c, i| {
            if (i >= 512) break;
            upper[i] = std.ascii.toUpper(c);
        }
        output = std.fmt.bufPrintZ(result[0..], "Uppercase: {s}", .{upper[0..@min(input_data.len, 512)]}) catch "Error";
    } else if (std.mem.eql(u8, operation, "hash")) {
        // Simple hash (sum of bytes)
        var hash: u32 = 0;
        for (input_data) |c| {
            hash = hash *% 31 +% c;
        }
        output = std.fmt.bufPrintZ(result[0..], "Hash: {X}", .{hash}) catch "Error";
    } else {
        output = "Unknown operation";
    }

    e.returnString(output);
}

fn executeCommand(e: *webui.Event, command: [:0]const u8, args: [:0]const u8) void {
    std.debug.print("Execute command: {s} {s}\n", .{ command, args });

    var response: [512]u8 = undefined;
    var result: [:0]const u8 = "";

    if (std.mem.eql(u8, command, "echo")) {
        result = std.fmt.bufPrintZ(response[0..], "Echo: {s}", .{args}) catch "Error";
    } else if (std.mem.eql(u8, command, "time")) {
        const timestamp = std.time.timestamp();
        result = std.fmt.bufPrintZ(response[0..], "Current time: {}", .{timestamp}) catch "Error";
    } else if (std.mem.eql(u8, command, "random")) {
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        const random_num = prng.random().int(u32);
        result = std.fmt.bufPrintZ(response[0..], "Random number: {}", .{random_num}) catch "Error";
    } else if (std.mem.eql(u8, command, "memory")) {
        // Simple memory info (simulated)
        result = std.fmt.bufPrintZ(response[0..], "Memory usage: {}MB", .{50 + @rem(std.time.timestamp(), 100)}) catch "Error";
    } else {
        result = "Unknown command";
    }

    e.returnString(result);
}

fn getSystemInfo(e: *webui.Event) void {
    const builtin = @import("builtin");

    var buffer: [1024]u8 = undefined;
    const info = std.fmt.bufPrintZ(buffer[0..],
        \\{{"os":"{s}","arch":"{s}","zigVersion":"{s}","webuiVersion":"2.5.0","timestamp":{}}}
    , .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch), @import("builtin").zig_version_string, std.time.timestamp() }) catch "{}";

    e.returnString(info);
}

fn testPerformance(e: *webui.Event, iterations: i64, operation: [:0]const u8) void {
    const start_time = std.time.nanoTimestamp();

    var i: i64 = 0;
    var result: u64 = 0;

    if (std.mem.eql(u8, operation, "math")) {
        while (i < iterations) : (i += 1) {
            result = result +% (@as(u64, @intCast(i)) * @as(u64, @intCast(i)));
        }
    } else if (std.mem.eql(u8, operation, "string")) {
        var buffer: [64]u8 = undefined;
        while (i < iterations) : (i += 1) {
            _ = std.fmt.bufPrint(buffer[0..], "test{}", .{i}) catch continue;
        }
    }

    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    var response: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(response[0..], "Performance test completed: {} iterations of {s} in {d:.2}ms", .{ iterations, operation, duration_ms }) catch "Error";

    e.returnString(msg);
    std.debug.print("Performance test: {} iterations in {d:.2}ms\n", .{ iterations, duration_ms });
}

fn manageSettings(e: *webui.Event, action: [:0]const u8, key: [:0]const u8, value: [:0]const u8) void {
    std.debug.print("Settings: {s} {s} = {s}\n", .{ action, key, value });

    var response: [512]u8 = undefined;
    var result: [:0]const u8 = "";

    if (std.mem.eql(u8, action, "set")) {
        // Store setting in memory
        const key_copy = allocator.dupe(u8, key) catch {
            result = "Error: Memory allocation failed for key";
            e.returnString(result);
            return;
        };
        const value_copy = allocator.dupe(u8, value) catch {
            allocator.free(key_copy);
            result = "Error: Memory allocation failed for value";
            e.returnString(result);
            return;
        };

        // Remove old value if exists
        if (settings_map.get(key)) |old_value| {
            allocator.free(old_value);
        }

        settings_map.put(key_copy, value_copy) catch {
            allocator.free(key_copy);
            allocator.free(value_copy);
            result = "Error: Failed to store setting";
            e.returnString(result);
            return;
        };

        result = std.fmt.bufPrintZ(response[0..], "Setting '{s}' set to '{s}'", .{ key, value }) catch "Error";
    } else if (std.mem.eql(u8, action, "get")) {
        // Get setting from memory
        if (settings_map.get(key)) |stored_value| {
            result = std.fmt.bufPrintZ(response[0..], "Setting '{s}' = '{s}'", .{ key, stored_value }) catch "Error";
        } else {
            result = std.fmt.bufPrintZ(response[0..], "Setting '{s}' not found (no value set)", .{key}) catch "Error";
        }
    } else if (std.mem.eql(u8, action, "delete")) {
        // Delete setting from memory
        if (settings_map.fetchRemove(key)) |kv| {
            allocator.free(kv.key);
            allocator.free(kv.value);
            result = std.fmt.bufPrintZ(response[0..], "Setting '{s}' deleted", .{key}) catch "Error";
        } else {
            result = std.fmt.bufPrintZ(response[0..], "Setting '{s}' not found (nothing to delete)", .{key}) catch "Error";
        }
    } else {
        result = "Unknown settings action";
    }

    e.returnString(result);
}

fn uploadFile(e: *webui.Event, filename: [:0]const u8, content: [:0]const u8) void {
    std.debug.print("Upload file: {s} (size: {})\n", .{ filename, content.len });

    var response: [512]u8 = undefined;
    var result: [:0]const u8 = "";

    // Validate filename
    if (filename.len == 0) {
        result = "Error: Filename cannot be empty";
        e.returnString(result);
        return;
    }

    // Ensure public directory exists
    std.fs.cwd().makePath("examples/comprehensive/public") catch |err| {
        std.debug.print("Warning: Failed to create public directory: {}\n", .{err});
        // Continue anyway, maybe directory already exists
    };

    // Sanitize filename to avoid filesystem issues while preserving Unicode characters (including Chinese)
    var safe_filename: [512]u8 = undefined;
    var safe_len: usize = 0;

    // Use Zig's UTF-8 iterator to properly handle Unicode characters
    const utf8_view = std.unicode.Utf8View.init(filename) catch {
        // If filename is not valid UTF-8, use a default name
        const default_name = "uploaded_file.txt";
        @memcpy(safe_filename[0..default_name.len], default_name);
        safe_len = default_name.len;
        safe_filename[safe_len] = 0;
        return; // Exit early with default name
    };

    var iter = utf8_view.iterator();
    while (iter.nextCodepoint()) |codepoint| {
        if (safe_len >= 500) break; // Leave space for null terminator

        // Check if this is a filesystem-dangerous character (ASCII only)
        if (codepoint < 128) {
            const ascii_char = @as(u8, @intCast(codepoint));
            if (ascii_char == '/' or ascii_char == '\\' or ascii_char == ':' or
                ascii_char == '*' or ascii_char == '?' or ascii_char == '"' or
                ascii_char == '<' or ascii_char == '>' or ascii_char == '|' or
                ascii_char == 0)
            {
                // Replace dangerous characters with underscore
                safe_filename[safe_len] = '_';
                safe_len += 1;
            } else {
                // Safe ASCII character
                safe_filename[safe_len] = ascii_char;
                safe_len += 1;
            }
        } else {
            // Unicode character (including Chinese) - encode back to UTF-8
            var utf8_buffer: [4]u8 = undefined;
            const utf8_len = std.unicode.utf8Encode(codepoint, &utf8_buffer) catch {
                // If encoding fails, replace with underscore
                safe_filename[safe_len] = '_';
                safe_len += 1;
                continue;
            };

            // Check if we have enough space
            if (safe_len + utf8_len <= 500) {
                @memcpy(safe_filename[safe_len .. safe_len + utf8_len], utf8_buffer[0..utf8_len]);
                safe_len += utf8_len;
            } else {
                break; // No more space
            }
        }
    }
    safe_filename[safe_len] = 0; // null terminate

    // Create file path in public directory
    const file_path = std.fmt.allocPrint(allocator, "examples/comprehensive/public/{s}", .{safe_filename[0..safe_len :0]}) catch {
        result = "Error: Failed to create file path";
        e.returnString(result);
        return;
    };
    defer allocator.free(file_path);

    std.debug.print("Creating file at: {s}\n", .{file_path});

    // Create file
    const file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
        std.debug.print("Failed to create file {s}: {}\n", .{ file_path, err });
        result = std.fmt.bufPrintZ(response[0..], "Error: Failed to create file '{s}' ({s})", .{ filename, @errorName(err) }) catch "Error";
        e.returnString(result);
        return;
    };
    defer file.close();

    // Write content to file
    file.writeAll(content) catch |err| {
        std.debug.print("Failed to write to file {s}: {}\n", .{ file_path, err });
        result = std.fmt.bufPrintZ(response[0..], "Error: Failed to write to file '{s}' ({s})", .{ filename, @errorName(err) }) catch "Error";
        e.returnString(result);
        return;
    };

    // Update counters
    app_state.files_uploaded += 1;

    // Return success message
    result = std.fmt.bufPrintZ(response[0..], "File '{s}' uploaded successfully as '{s}'. Size: {} bytes. Total files: {}", .{ filename, safe_filename[0..safe_len :0], content.len, app_state.files_uploaded }) catch "Error";
    e.returnString(result);
}
