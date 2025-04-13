const std = @import("std");
const webui = @import("webui");

// general purpose allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
// allocator
const allocator = gpa.allocator();

var private_input_arr = std.mem.zeroes([256]?[]u8);
var public_input = std.mem.zeroes(?[]u8);
var users_count: usize = 0;
var tab_count: usize = 0;

fn exit_app(_: *webui.Event) void {
    // Close all opened windows
    webui.exit();
}

fn save(e: *webui.Event) void {
    // Get input value
    const privateInput = e.getString();

    // free previous memory
    if (private_input_arr[e.client_id]) |val|
        allocator.free(val);

    // allocate new memory, to save new private input
    private_input_arr[e.client_id] = allocator.dupe(u8, privateInput) catch unreachable;
}

fn saveAll(e: *webui.Event) void {
    // Get input value
    const publicInput = e.getString();

    // free previous memory
    if (public_input) |val|
        allocator.free(val);

    // allocate new memory to save new public input
    public_input = allocator.dupe(u8, publicInput) catch unreachable;

    // general new js
    const js = std.fmt.allocPrintZ(
        allocator,
        "document.getElementById(\"publicInput\").value = \"{s}\";",
        .{publicInput},
    ) catch unreachable;
    // free js
    defer allocator.free(js);

    var win = e.getWindow();
    win.run(js);
}

fn events(e: *webui.Event) void {
    // This function gets called every time
    // there is an event

    // Full web browser cookies
    // const cookies = e.cookies;

    // Static client (Based on web browser cookies)
    const client_id = e.client_id;

    // Dynamic client connection ID (Changes on connect/disconnect events)
    const connection_id = e.connection_id;

    if (e.event_type == .EVENT_CONNECTED) {
        // New connection
        if (users_count < (client_id + 1))
            users_count = client_id + 1;
        tab_count += 1;
    } else if (e.event_type == .EVENT_DISCONNECTED) {
        // Disconnection
        if (tab_count > 0)
            tab_count -= 1;
    }

    // Buffer

    // Update this current user only

    e.runClient("document.getElementById(\"status\").innerText = \"Connected!\";");

    // userNumber
    {
        var buffer = std.mem.zeroes([2048]u8);
        const js = std.fmt.bufPrintZ(
            &buffer,
            "document.getElementById(\"userNumber\").innerText = \"{}\";",
            .{client_id},
        ) catch unreachable;
        e.runClient(js);
    }

    // connectionNumber
    {
        var buffer = std.mem.zeroes([2048]u8);
        const js = std.fmt.bufPrintZ(
            &buffer,
            "document.getElementById(\"connectionNumber\").innerText = \"{}\";",
            .{connection_id},
        ) catch unreachable;
        e.runClient(js);
    }

    // privateInput
    {
        const val = if (private_input_arr[client_id]) |val| val else "";

        var buffer = std.mem.zeroes([2048]u8);
        const js = std.fmt.bufPrintZ(
            &buffer,
            "document.getElementById(\"privateInput\").value = \"{s}\";",
            .{val},
        ) catch unreachable;
        e.runClient(js);
    }

    // publicInput
    {
        const val = if (public_input) |val| val else "";
        var buffer = std.mem.zeroes([2048]u8);
        const js = std.fmt.bufPrintZ(
            &buffer,
            "document.getElementById(\"publicInput\").value = \"{s}\";",
            .{val},
        ) catch unreachable;
        e.runClient(js);
    }

    // Update all connected users

    var win = e.getWindow();
    // userCount
    {
        var buffer = std.mem.zeroes([2048]u8);
        const js = std.fmt.bufPrintZ(
            &buffer,
            "document.getElementById(\"userCount\").innerText = \"{}\";",
            .{users_count},
        ) catch unreachable;
        win.run(js);
    }

    // tabCount
    {
        var buffer = std.mem.zeroes([2048]u8);
        const js = std.fmt.bufPrintZ(
            &buffer,
            "document.getElementById(\"tabCount\").innerText = \"{}\";",
            .{tab_count},
        ) catch unreachable;
        win.run(js);
    }
}

pub fn main() !void {
    defer {
        const deinit_status = gpa.deinit();

        if (deinit_status == .leak) @panic("memory leak!");
    }

    // when program exit, we will free all memory allocated!
    defer {
        for (private_input_arr) |val| {
            if (val) |v|
                allocator.free(v);
        }
        if (public_input) |val|
            allocator.free(val);
    }

    // Allow multi-user connection
    webui.setConfig(.multi_client, true);

    // Allow cookies
    webui.setConfig(.use_cookies, true);

    // Create new window
    var win = webui.newWindow();

    // Bind HTML with a Zig functions
    _ = try win.bind("save", save);
    _ = try win.bind("saveAll", saveAll);
    _ = try win.bind("exit_app", exit_app);

    // Bind all events
    _ = try win.bind("", events);

    // Start server only
    const url = try win.startServer("index.html");

    // Open a new page in the default native web browser
    webui.openUrl(@as([*c]const u8, @ptrCast(url.ptr))[0..url.len :0]);

    // Wait until all windows get closed
    webui.wait();

    // Free all memory resources (Optional)
    webui.clean();
}
