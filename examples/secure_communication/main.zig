const std = @import("std");
const webui = @import("webui");

pub fn main() !void {
    const window = webui.newWindow();
    defer window.destroy();

    // Set up TLS certificate (only works with webui-2-secure library)
    // In production, use real certificates
    // webui.setTlsCertificate("", "") catch {
    //     std.debug.print("TLS not supported in this build\n", .{});
    // };

    // Bind events for secure communication
    _ = try window.bind("encode_data", encodeData);
    _ = try window.bind("decode_data", decodeData);
    _ = try window.bind("send_binary", sendBinaryData);
    _ = try window.bind("test_memory", testMemoryManagement);

    // Show the window
    try window.show("index.html");

    // Wait for the window to close
    webui.wait();
}

fn encodeData(e: *webui.Event) void {
    // Get the data to encode from JavaScript
    const data = e.getString();

    std.debug.print("Encoding data: {s}\n", .{data});

    // Encode the data using WebUI's base64 encoding
    const encoded = webui.encode(data) catch |err| {
        std.debug.print("Encoding failed: {}\n", .{err});
        e.returnString("Encoding failed");
        return;
    };
    defer webui.free(encoded);

    // Create null-terminated string for return
    var result_buffer: [1024]u8 = undefined;
    const len = @min(encoded.len, result_buffer.len - 1);
    @memcpy(result_buffer[0..len], encoded[0..len]);
    result_buffer[len] = 0;

    e.returnString(result_buffer[0..len :0]);
}

fn decodeData(e: *webui.Event) void {
    // Get the base64 data to decode
    const encoded_data = e.getString();

    std.debug.print("Decoding data: {s}\n", .{encoded_data});

    // Decode the data
    const decoded = webui.decode(encoded_data) catch |err| {
        std.debug.print("Decoding failed: {}\n", .{err});
        e.returnString("Decoding failed");
        return;
    };
    defer webui.free(decoded);

    // Create null-terminated string for return
    var result_buffer: [1024]u8 = undefined;
    const len = @min(decoded.len, result_buffer.len - 1);
    @memcpy(result_buffer[0..len], decoded[0..len]);
    result_buffer[len] = 0;

    e.returnString(result_buffer[0..len :0]);
}

fn sendBinaryData(e: *webui.Event) void {
    const window = e.getWindow();

    // Create some binary data
    var binary_data = [_]u8{ 0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x57, 0x6F, 0x72, 0x6C, 0x64, 0x21 };

    // Send raw binary data to the UI
    window.sendRaw("receiveBinaryData", &binary_data);

    // Also demonstrate sending to specific client
    e.sendRawClient("receiveClientData", &binary_data);

    e.returnString("Binary data sent");
}

fn testMemoryManagement(e: *webui.Event) void {
    // Demonstrate WebUI's memory management

    // Allocate memory using WebUI's allocator
    const size: usize = 256;
    const buffer = webui.malloc(size) catch |err| {
        std.debug.print("Memory allocation failed: {}\n", .{err});
        e.returnString("Memory allocation failed");
        return;
    };
    defer webui.free(buffer);

    // Fill buffer with test data
    const test_data = "This is test data for memory management";
    const copy_len = @min(test_data.len, buffer.len);
    webui.memcpy(buffer[0..copy_len], test_data[0..copy_len]);

    // Create another buffer and copy data
    const buffer2 = webui.malloc(size) catch {
        e.returnString("Second allocation failed");
        return;
    };
    defer webui.free(buffer2);

    webui.memcpy(buffer2[0..copy_len], buffer[0..copy_len]);

    // Return the copied data
    buffer2[copy_len] = 0;
    e.returnString(buffer2[0..copy_len :0]);
}
