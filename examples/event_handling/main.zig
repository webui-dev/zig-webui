//! WebUI Zig - Event Handling and Context Management Example
//! This example demonstrates advanced event handling, context management, and multi-client support
const std = @import("std");
const webui = @import("webui");

const html = @embedFile("index.html");

var allocator = std.heap.page_allocator;

// Global user context storage for each window/client
var global_user_contexts: ?std.AutoHashMap(usize, *UserContext) = null;

// Online user structure
const OnlineUser = struct {
    client_id: usize,
    username: []const u8,
};

// Online users list for tracking connected clients
var online_users: ?std.ArrayList(OnlineUser) = null;

// Initialize global user contexts if not already initialized
fn ensureContextsInitialized() void {
    if (global_user_contexts == null) {
        global_user_contexts = std.AutoHashMap(usize, *UserContext).init(allocator);
    }
    if (online_users == null) {
        online_users = std.ArrayList(OnlineUser).init(allocator);
    }
}

// Get the global contexts map (ensuring it's initialized)
fn getContextsMap() *std.AutoHashMap(usize, *UserContext) {
    ensureContextsInitialized();
    return &global_user_contexts.?;
}

// User data structure for context
const UserContext = struct {
    user_id: u32,
    username: []const u8,
    session_start: i64,
    click_count: u32,
    
    fn create(user_id: u32, username: []const u8) !*UserContext {
        const context = try allocator.create(UserContext);
        context.* = UserContext{
            .user_id = user_id,
            .username = try allocator.dupe(u8, username),
            .session_start = std.time.timestamp(),
            .click_count = 0,
        };
        return context;
    }
    
    fn destroy(self: *UserContext) void {
        allocator.free(self.username);
        allocator.destroy(self);
    }
};

pub fn main() !void {
    // Configure for multi-client support
    webui.setConfig(.multi_client, true);  // Enable multi-client mode
    webui.setConfig(.use_cookies, true);   // Use cookies for client identification
    
    // Set public access to allow connections from other devices
    // This allows other devices on the same network to connect
    
    // Create window
    var nwin = webui.newWindow();
    
    // Allow public network access (other devices can connect)
    nwin.setPublic(true);
    
    // Set event blocking mode
    nwin.setEventBlocking(false); // Non-blocking events
    
    // Bind event handlers with context
    _ = try nwin.bind("user_login", userLogin);
    _ = try nwin.bind("user_logout", userLogout);
    _ = try nwin.bind("track_click", trackClick);
    _ = try nwin.bind("get_user_info", getUserInfo);
    _ = try nwin.bind("get_online_users", getOnlineUsers);
    _ = try nwin.bind("send_message", sendMessage);
    _ = try nwin.bind("broadcast_message", broadcastMessage);
    _ = try nwin.bind("client_connect", clientConnect);
    _ = try nwin.bind("client_disconnect", clientDisconnect);
    
    // Bind interface handlers for advanced event management
    _ = try nwin.interfaceBind("interface_handler", interfaceEventHandler);
    
    // Bind universal event handler (empty element name = all events)
    _ = try nwin.bind("", universalEventHandler);
    
    // Show window with multi-client support
    // Try to show embedded HTML first
    nwin.show(html) catch |err| {
        // If that fails, try alternative approach
        std.debug.print("Warning: Failed to show embedded HTML ({}), trying alternative method...\n", .{err});
        
        // Write HTML to temporary file and use startServer
        const temp_file = "temp_index.html";
        const file = std.fs.cwd().createFile(temp_file, .{}) catch |file_err| {
            std.debug.print("Error: Could not create temporary HTML file: {}\n", .{file_err});
            return;
        };
        defer file.close();
        defer std.fs.cwd().deleteFile(temp_file) catch {};
        
        file.writeAll(html) catch |write_err| {
            std.debug.print("Error: Could not write HTML content: {}\n", .{write_err});
            return;
        };
        
        // Start server with file
        const url = nwin.startServer(temp_file) catch |server_err| {
            std.debug.print("Error: Could not start server: {}\n", .{server_err});
            return;
        };
        
        std.debug.print("📍 Server URL: {s}\n", .{url});
        
        // Open in default browser
        webui.openUrl(@as([*c]const u8, @ptrCast(url.ptr))[0..url.len :0]);
    };
    
    // Get and display server information
    const port = nwin.getPort() catch |err| blk: {
        std.debug.print("Warning: Could not get server port ({})\n", .{err});
        break :blk @as(usize, 0);
    };
    
    const url = nwin.getUrl() catch |err| blk: {
        std.debug.print("Warning: Could not get server URL ({})\n", .{err});
        break :blk @as([:0]const u8, "unknown");
    };
    
    // Print multi-client instructions
    std.debug.print("\n🌐 Multi-Client Event Handling Server Started!\n", .{});
    std.debug.print("📍 Server URL: {s}\n", .{url});
    std.debug.print("🔌 Server Port: {}\n", .{port});
    std.debug.print("🏠 Local Access: http://localhost:{}\n", .{port});
    std.debug.print("🌍 Network Access: http://[YOUR_IP]:{}\n", .{port});
    std.debug.print("\n💡 To find your IP address:\n", .{});
    std.debug.print("   Windows: ipconfig | findstr IPv4\n", .{});
    std.debug.print("   Mac/Linux: ifconfig | grep inet\n", .{});
    std.debug.print("   Or check in network settings\n", .{});
    std.debug.print("\n" ++ "=" ** 60 ++ "\n", .{});
    std.debug.print("\n📋 How to test multi-client functionality:\n", .{});
    std.debug.print("\n🔗 Multi-Client Connection Methods:\n", .{});
    std.debug.print("   1. SAME COMPUTER - New Tab/Window:\n", .{});
    std.debug.print("      → Copy: {s}\n", .{url});
    std.debug.print("      → Paste in new browser tab\n", .{});
    std.debug.print("\n   2. SAME COMPUTER - Different Browser:\n", .{});
    std.debug.print("      → Chrome: {s}\n", .{url});
    std.debug.print("      → Firefox: {s}\n", .{url});
    std.debug.print("      → Edge: {s}\n", .{url});
    std.debug.print("\n   3. OTHER DEVICES (Phone/Tablet/PC):\n", .{});
    std.debug.print("      → Find your IP address using commands above\n", .{});
    std.debug.print("      → Replace localhost with your IP\n", .{});
    std.debug.print("      → Example: http://192.168.1.100:{}\n", .{port});
    std.debug.print("\n👥 Suggested Test Users:\n", .{});
    std.debug.print("   🟦 Window 1: Alice (ID: 1001)\n", .{});
    std.debug.print("   🟩 Window 2: Bob (ID: 1002)\n", .{});
    std.debug.print("   🟨 Window 3: Carol (ID: 1003)\n", .{});
    std.debug.print("   🟪 Window 4: David (ID: 1004)\n", .{});
    std.debug.print("\n🎯 Test Features:\n", .{});
    std.debug.print("   • Login with different users\n", .{});
    std.debug.print("   • Refresh online user list (🔄 button)\n", .{});
    std.debug.print("   • Send direct messages between users\n", .{});
    std.debug.print("   • Test broadcast messages\n", .{});
    std.debug.print("   • Click tracking per user\n\n", .{});
    
    std.debug.print("Event handling server started. Multi-client support enabled.\n", .{});
    
    // Wait for all windows to close
    webui.wait();
    
    // Clean up any remaining contexts
    cleanupAllContexts();
    webui.clean();
}

fn getLocalIPAddress() ![]const u8 {
    // Placeholder function - user should check their actual IP address
    // Use the commands shown in the console output to find your real IP
    return "192.168.x.x";
}

fn userLogin(e: *webui.Event) void {
    const username = e.getString();
    const user_id = @as(u32, @intCast(e.getIntAt(1)));
    
    std.debug.print("User login attempt: {} - {s}\n", .{user_id, username});
    
    // Create user context
    const context = UserContext.create(user_id, username) catch {
        e.returnString("Login failed: Unable to create user context");
        return;
    };
    
    // Set context for this element
    const win = e.getWindow();
    // Set context for the calling element and make it available globally
    // We'll use a window-wide context storage
    win.setContext("user_login", @ptrCast(context));
    
    // Store context globally using client ID as key
    getContextsMap().put(e.client_id, context) catch {
        std.debug.print("Failed to store global context for client {}\n", .{e.client_id});
    };
    
    // Add user to online list
    ensureContextsInitialized();
    if (online_users) |*users| {
        users.append(OnlineUser{ .client_id = e.client_id, .username = context.username }) catch {
            std.debug.print("Failed to add user to online list\n", .{});
        };
    }
    
    // Broadcast user list update to all clients
    broadcastUserListUpdate();
    
    // Return success response
    var response: [257]u8 = undefined; // +1 for null terminator
    const msg = std.fmt.bufPrint(response[0..256], 
        "Welcome {s}! User ID: {}, Session started.", .{username, user_id}) catch "";
    
    // Ensure null termination
    response[msg.len] = 0;
    const null_terminated: [:0]const u8 = response[0..msg.len :0];
    e.returnString(null_terminated);
    std.debug.print("User {s} logged in successfully\n", .{username});
}

fn userLogout(e: *webui.Event) void {
    // Get user context from global storage
    const context = getContextsMap().get(e.client_id) orelse {
        e.returnString("No active session found");
        return;
    };
    
    // Calculate session duration
    const session_duration = std.time.timestamp() - context.session_start;
    
    var response: [257]u8 = undefined; // +1 for null terminator
    const msg = std.fmt.bufPrint(response[0..256], 
        "Goodbye {s}! Session duration: {}s, Total clicks: {}", 
        .{context.username, session_duration, context.click_count}) catch "";
    
    // Ensure null termination
    response[msg.len] = 0;
    const null_terminated: [:0]const u8 = response[0..msg.len :0];
    e.returnString(null_terminated);
    std.debug.print("User {s} logged out. Session: {}s\n", .{context.username, session_duration});
    
    // Remove from global context storage
    _ = getContextsMap().remove(e.client_id);
    
    // Remove from online users list
    if (online_users) |*users| {
        var i: usize = 0;
        while (i < users.items.len) {
            if (users.items[i].client_id == e.client_id) {
                _ = users.orderedRemove(i);
                break;
            }
            i += 1;
        }
    }
    
    // Broadcast user list update to all clients
    broadcastUserListUpdate();
    
    // Clean up context
    context.destroy();
}

fn trackClick(e: *webui.Event) void {
    const button_name = e.getString();
    
    // Get user context from global storage
    const context = getContextsMap().get(e.client_id) orelse {
        e.returnString("No active session - please login first");
        return;
    };
    
    context.click_count += 1;
    
    var response: [257]u8 = undefined; // +1 for null terminator
    const msg = std.fmt.bufPrint(response[0..256], 
        "Button '{s}' clicked by {s}. Total clicks: {}", 
        .{button_name, context.username, context.click_count}) catch "";
    
    // Ensure null termination
    response[msg.len] = 0;
    const null_terminated: [:0]const u8 = response[0..msg.len :0];
    e.returnString(null_terminated);
    std.debug.print("Click tracked: {s} by {s} ({})\n", .{button_name, context.username, context.click_count});
}

fn getUserInfo(e: *webui.Event) void {
    // Get user context from global storage
    const context = getContextsMap().get(e.client_id) orelse {
        e.returnString("{\"error\":\"No active session\"}");
        return;
    };
    
    const session_time = std.time.timestamp() - context.session_start;
    
    var response: [513]u8 = undefined; // +1 for null terminator
    const json = std.fmt.bufPrint(response[0..512], 
        "{{\"userId\":{},\"username\":\"{s}\",\"sessionTime\":{},\"clickCount\":{},\"clientId\":{}}}", 
        .{context.user_id, context.username, session_time, context.click_count, e.client_id}) catch "";
    
    // Ensure null termination
    response[json.len] = 0;
    const null_terminated: [:0]const u8 = response[0..json.len :0];
    e.returnString(null_terminated);
}

fn sendMessage(e: *webui.Event) void {
    const message = e.getString();
    const target_client = e.getIntAt(1);
    
    // Get sender context from global storage
    const context = getContextsMap().get(e.client_id) orelse {
        e.returnString("Authentication required");
        return;
    };
    
    // In a real application, you would send to specific client
    // For this example, we'll just log the message
    std.debug.print("Message from {s} to client {}: {s}\n", .{context.username, target_client, message});
    
    // Send message to specific client (simulated)
    const win = e.getWindow();
    var js_code: [513]u8 = undefined; // +1 for null terminator
    const script = std.fmt.bufPrint(js_code[0..512], 
        "receiveMessage('{s}', '{s}');", .{context.username, message}) catch return;
    
    // Ensure null termination
    js_code[script.len] = 0;
    const null_terminated: [:0]const u8 = js_code[0..script.len :0];
    win.run(null_terminated);
    
    e.returnString("Message sent");
}

fn broadcastUserListUpdate() void {
    // Create JSON list of online users
    var users_json: [1024]u8 = undefined;
    var json_content: []const u8 = undefined;
    
    if (online_users) |users| {
        var stream = std.io.fixedBufferStream(&users_json);
        var writer = stream.writer();
        
        writer.writeAll("[") catch return;
        for (users.items, 0..) |user, i| {
            if (i > 0) writer.writeAll(",") catch return;
            writer.print("{{\"clientId\":{},\"username\":\"{s}\"}}", .{user.client_id, user.username}) catch return;
        }
        writer.writeAll("]") catch return;
        
        json_content = stream.getWritten();
    } else {
        json_content = "[]";
    }
    
    // Broadcast to all windows (this is a simplified approach)
    // In a real implementation, you'd iterate through all active windows
    std.debug.print("Broadcasting user list update: {s}\n", .{json_content});
    
    // Note: This is a simplified version. In a full implementation,
    // you would need to track all active windows and send to each one.
}

fn getOnlineUsers(e: *webui.Event) void {
    // Return list of online users as JSON
    var users_json: [1024]u8 = undefined;
    var json_content: []const u8 = undefined;
    
    if (online_users) |users| {
        var stream = std.io.fixedBufferStream(&users_json);
        var writer = stream.writer();
        
        writer.writeAll("[") catch {
            e.returnString("[]");
            return;
        };
        for (users.items, 0..) |user, i| {
            if (i > 0) writer.writeAll(",") catch continue;
            writer.print("{{\"clientId\":{},\"username\":\"{s}\"}}", .{user.client_id, user.username}) catch continue;
        }
        writer.writeAll("]") catch {
            e.returnString("[]");
            return;
        };
        
        json_content = stream.getWritten();
    } else {
        json_content = "[]";
    }
    
    var response: [1025]u8 = undefined;
    std.mem.copyForwards(u8, response[0..json_content.len], json_content);
    response[json_content.len] = 0;
    const null_terminated: [:0]const u8 = response[0..json_content.len :0];
    e.returnString(null_terminated);
}

fn broadcastMessage(e: *webui.Event) void {
    const message = e.getString();
    
    // Get sender context from global storage
    const context = getContextsMap().get(e.client_id) orelse {
        e.returnString("Authentication required");
        return;
    };
    
    std.debug.print("Broadcast from {s}: {s}\n", .{context.username, message});
    
    // Broadcast to all clients
    const win = e.getWindow();
    var js_code: [513]u8 = undefined; // +1 for null terminator
    const script = std.fmt.bufPrint(js_code[0..512], 
        "receiveBroadcast('{s}', '{s}');", .{context.username, message}) catch return;
    
    // Ensure null termination
    js_code[script.len] = 0;
    const null_terminated: [:0]const u8 = js_code[0..script.len :0];
    win.run(null_terminated);
    
    e.returnString("Message broadcasted to all clients");
}

fn clientConnect(e: *webui.Event) void {
    std.debug.print("Client connected: ID={}, Connection={}\n", .{e.client_id, e.connection_id});
    
    // Send welcome message to the specific client
    e.runClient("showNotification('Connected to server');");
    
    var response: [129]u8 = undefined; // +1 for null terminator
    const msg = std.fmt.bufPrint(response[0..128], 
        "Client {} connected", .{e.client_id}) catch "";
    
    // Ensure null termination
    response[msg.len] = 0;
    const null_terminated: [:0]const u8 = response[0..msg.len :0];
    e.returnString(null_terminated);
}

fn clientDisconnect(e: *webui.Event) void {
    std.debug.print("Client disconnected: ID={}, Connection={}\n", .{e.client_id, e.connection_id});
    
    // Clean up any client-specific resources
    e.closeClient();
}

fn universalEventHandler(e: *webui.Event) void {
    // This handler catches all events
    std.debug.print("Universal handler - Event: {s}, Client: {}, Type: {}\n", 
        .{e.element, e.client_id, e.event_type});
    
    // You could implement global logging, analytics, or security checks here
}

fn interfaceEventHandler(
    window_handle: usize,
    event_type: webui.EventKind,
    element: []u8,
    event_number: usize,
    bind_id: usize,
) void {
    std.debug.print("Interface handler - Window: {}, Type: {}, Element: {s}, Event: {}, Bind: {}\n", 
        .{window_handle, event_type, element, event_number, bind_id});
    
    // Advanced event processing using interface API
    const win = webui{ .window_handle = window_handle };
    
    // Get event data using interface methods
    const arg_count = win.interfaceGetSizeAt(event_number, 0);
    if (arg_count > 0) {
        const first_arg = win.interfaceGetStringAt(event_number, 0);
        std.debug.print("First argument: {s}\n", .{first_arg});
    }
    
    // Set response using interface
    win.interfaceSetResponse(event_number, "Interface handler processed event");
}

fn cleanupAllContexts() void {
    // In a real application, you would maintain a list of all contexts
    // and clean them up here
    // Clean up all remaining user contexts
    if (global_user_contexts) |*contexts| {
        var iterator = contexts.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.destroy();
        }
        contexts.clearAndFree();
    }
    
    std.debug.print("Cleaning up all user contexts...\n", .{});
}
