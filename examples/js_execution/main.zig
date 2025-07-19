//! WebUI Zig - JavaScript Execution and Communication Example
//! This example demonstrates running JavaScript from Zig and advanced communication
const std = @import("std");
const webui = @import("webui");

const html = @embedFile("index.html");

var allocator = std.heap.page_allocator;

pub fn main() !void {
    // Create window
    var nwin = webui.newWindow();
    
    // Set runtime for JavaScript execution
    nwin.setRuntime(.NodeJS);
    
    // Bind functions for JavaScript execution
    _ = try nwin.binding("run_simple_js", runSimpleJs);
    _ = try nwin.binding("run_js_with_response", runJsWithResponse);
    _ = try nwin.binding("run_complex_js", runComplexJs);
    _ = try nwin.binding("send_data_to_js", sendDataToJs);
    _ = try nwin.binding("send_raw_data", sendRawData);
    _ = try nwin.binding("navigate_to_url", navigateToUrl);
    _ = try nwin.binding("get_page_content", getPageContent);
    _ = try nwin.binding("manipulate_dom", manipulateDom);
    _ = try nwin.binding("handle_json_data", handleJsonData);

    // Show window
    try nwin.show(html);
    
    // Wait for window to close
    webui.wait();
    
    // Clean up
    webui.clean();
}

fn runSimpleJs(e: *webui.Event) void {
    const win = e.getWindow();
    
    // Run JavaScript without waiting for response
    win.run("alert('Hello from Zig!'); console.log('JavaScript executed from Zig');");
    
    e.returnString("Simple JavaScript executed");
    std.debug.print("Executed simple JavaScript\n", .{});
}

fn runJsWithResponse(e: *webui.Event, operation: [:0]const u8, a: i64, b: i64) void {
    const win = e.getWindow();
    
    // Prepare JavaScript code based on operation
    var js_code: [256]u8 = undefined;
    const script = switch (std.mem.eql(u8, operation, "add")) {
        true => std.fmt.bufPrint(js_code[0..], "return {} + {};", .{a, b}),
        false => switch (std.mem.eql(u8, operation, "multiply")) {
            true => std.fmt.bufPrint(js_code[0..], "return {} * {};", .{a, b}),
            false => switch (std.mem.eql(u8, operation, "power")) {
                true => std.fmt.bufPrint(js_code[0..], "return Math.pow({}, {});", .{a, b}),
                false => std.fmt.bufPrint(js_code[0..], "return 'Unknown operation';", .{}),
            },
        },
    } catch return;

    // Execute JavaScript and get response
    var response_buffer: [64]u8 = undefined;
    // Ensure script is null-terminated by creating a proper null-terminated string
    var null_terminated_script: [257]u8 = undefined; // +1 for null terminator
    @memcpy(null_terminated_script[0..script.len], script);
    null_terminated_script[script.len] = 0;
    const script_z: [:0]const u8 = null_terminated_script[0..script.len :0];
    
    win.script(script_z, 5, response_buffer[0..]) catch {
        e.returnString("JavaScript execution failed");
        return;
    };
    
    // Find the null terminator
    var response_len: usize = 0;
    for (response_buffer) |c| {
        if (c == 0) break;
        response_len += 1;
    }
    
    e.returnString(response_buffer[0..response_len :0]);
    std.debug.print("JavaScript result: {s}\n", .{response_buffer[0..response_len]});
}

fn runComplexJs(e: *webui.Event, data: [:0]const u8) void {
    const win = e.getWindow();
    
    // Complex JavaScript that processes data and returns result
    var js_code: [512]u8 = undefined;
    const script = std.fmt.bufPrint(js_code[0..], 
        \\const data = '{s}';
        \\const result = {{
        \\  original: data,
        \\  length: data.length,
        \\  uppercase: data.toUpperCase(),
        \\  words: data.split(' ').length,
        \\  reversed: data.split('').reverse().join(''),
        \\  timestamp: new Date().toISOString()
        \\}};
        \\return JSON.stringify(result);
    , .{data}) catch return;

    var response_buffer: [1024]u8 = undefined;
    // Ensure script is null-terminated
    var null_terminated_script: [513]u8 = undefined; // +1 for null terminator
    @memcpy(null_terminated_script[0..script.len], script);
    null_terminated_script[script.len] = 0;
    const script_z: [:0]const u8 = null_terminated_script[0..script.len :0];
    
    win.script(script_z, 10, response_buffer[0..]) catch {
        e.returnString("Complex JavaScript execution failed");
        return;
    };
    
    // Find response length
    var response_len: usize = 0;
    for (response_buffer) |c| {
        if (c == 0) break;
        response_len += 1;
    }
    
    e.returnString(response_buffer[0..response_len :0]);
    std.debug.print("Complex JavaScript result: {s}\n", .{response_buffer[0..response_len]});
}

fn sendDataToJs(e: *webui.Event, message: [:0]const u8, value: i64) void {
    const win = e.getWindow();
    
    // Create data structure to send
    var data: [256]u8 = undefined;
    const json_data = std.fmt.bufPrint(data[0..], 
        "{{\"message\":\"{s}\",\"value\":{},\"timestamp\":{}}}", 
        .{message, value, std.time.timestamp()}) catch return;
    
    // Send data to JavaScript function
    var js_call: [512]u8 = undefined;
    const js_code = std.fmt.bufPrint(js_call[0..], 
        "receiveDataFromZig({s});", .{json_data}) catch return;
    
    // Ensure js_code is null-terminated
    var null_terminated_js: [513]u8 = undefined; // +1 for null terminator
    @memcpy(null_terminated_js[0..js_code.len], js_code);
    null_terminated_js[js_code.len] = 0;
    const js_code_z: [:0]const u8 = null_terminated_js[0..js_code.len :0];
    
    win.run(js_code_z);
    
    e.returnString("Data sent to JavaScript");
    std.debug.print("Sent data to JavaScript: {s}\n", .{json_data});
}

fn sendRawData(e: *webui.Event, size: i64) void {
    const win = e.getWindow();
    
    // Create raw binary data
    const data_size: usize = @intCast(@min(size, 1024));
    const raw_data = allocator.alloc(u8, data_size) catch return;
    defer allocator.free(raw_data);
    
    // Fill with sample data
    for (raw_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }
    
    // Send raw data to JavaScript
    win.sendRaw("receiveRawData", raw_data);
    
    var response: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(response[0..], 
        "Sent {} bytes of raw data", .{data_size}) catch return;
    
    // Ensure msg is null-terminated
    var null_terminated_msg: [65]u8 = undefined; // +1 for null terminator
    @memcpy(null_terminated_msg[0..msg.len], msg);
    null_terminated_msg[msg.len] = 0;
    const msg_z: [:0]const u8 = null_terminated_msg[0..msg.len :0];
    
    e.returnString(msg_z);
    std.debug.print("Sent raw data: {} bytes\n", .{data_size});
}

fn navigateToUrl(e: *webui.Event, url: [:0]const u8) void {
    const win = e.getWindow();
    
    if (std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://")) {
        win.navigate(url);
        e.returnString("Navigation initiated");
        std.debug.print("Navigating to: {s}\n", .{url});
    } else {
        e.returnString("Invalid URL - must start with http:// or https://");
    }
}

fn getPageContent(e: *webui.Event) void {
    const win = e.getWindow();
    
    const js_code = 
        \\return JSON.stringify({
        \\  title: document.title,
        \\  url: window.location.href,
        \\  userAgent: navigator.userAgent,
        \\  cookies: document.cookie,
        \\  elements: document.querySelectorAll('*').length
        \\});
    ;
    
    var response_buffer: [2048]u8 = undefined;
    win.script(js_code, 5, response_buffer[0..]) catch {
        e.returnString("Failed to get page content");
        return;
    };
    
    // Find response length
    var response_len: usize = 0;
    for (response_buffer) |c| {
        if (c == 0) break;
        response_len += 1;
    }
    
    e.returnString(response_buffer[0..response_len :0]);
    std.debug.print("Page content: {s}\n", .{response_buffer[0..response_len]});
}

fn manipulateDom(e: *webui.Event, element_id: [:0]const u8, new_text: [:0]const u8) void {
    const win = e.getWindow();
    
    var js_code: [512]u8 = undefined;
    const script = std.fmt.bufPrint(js_code[0..], 
        \\const element = document.getElementById('{s}');
        \\if (element) {{
        \\  element.innerHTML = '{s}';
        \\  element.style.background = 'rgba(0,255,0,0.2)';
        \\  setTimeout(() => element.style.background = '', 2000);
        \\  return 'Element updated successfully';
        \\}} else {{
        \\  return 'Element not found';
        \\}}
    , .{element_id, new_text}) catch return;

    var response_buffer: [128]u8 = undefined;
    // Ensure script is null-terminated
    var null_terminated_script: [513]u8 = undefined; // +1 for null terminator
    @memcpy(null_terminated_script[0..script.len], script);
    null_terminated_script[script.len] = 0;
    const script_z: [:0]const u8 = null_terminated_script[0..script.len :0];
    
    win.script(script_z, 5, response_buffer[0..]) catch {
        e.returnString("DOM manipulation failed");
        return;
    };
    
    // Find response length
    var response_len: usize = 0;
    for (response_buffer) |c| {
        if (c == 0) break;
        response_len += 1;
    }
    
    e.returnString(response_buffer[0..response_len :0]);
    std.debug.print("DOM manipulation result: {s}\n", .{response_buffer[0..response_len]});
}

fn handleJsonData(e: *webui.Event, json_str: [:0]const u8) void {
    // In a real application, you would parse the JSON properly
    // For this example, we'll just echo back some processed info
    
    var response: [512]u8 = undefined;
    const result = std.fmt.bufPrint(response[0..], 
        "Received JSON data: {s} (length: {})", .{json_str, json_str.len}) catch return;
    
    // Ensure result is null-terminated
    var null_terminated_result: [513]u8 = undefined; // +1 for null terminator
    @memcpy(null_terminated_result[0..result.len], result);
    null_terminated_result[result.len] = 0;
    const result_z: [:0]const u8 = null_terminated_result[0..result.len :0];
    
    e.returnString(result_z);
    std.debug.print("Processed JSON: {s}\n", .{json_str});
}