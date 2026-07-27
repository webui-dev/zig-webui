const std = @import("std");
const Linsang = @import("Linsang");
const browser = @import("browser.zig");
const protocol = @import("protocol.zig");

const bridge = @embedFile("bridge.js");

pub const Handler = *const fn (*Call, ?*anyopaque) anyerror!void;

const Binding = struct {
    name: []u8,
    handler: Handler,
    user_data: ?*anyopaque,
};

const WindowState = struct {
    gpa: std.mem.Allocator,
    html: []u8,
    token: u32 = 0,
    bindings: std.ArrayList(Binding) = .empty,

    fn deinit(self: *WindowState) void {
        for (self.bindings.items) |item| self.gpa.free(item.name);
        self.bindings.deinit(self.gpa);
        self.gpa.free(self.html);
        self.gpa.destroy(self);
    }

    fn binding(self: *WindowState, name: []const u8) ?Binding {
        // ponytail: binding counts are tiny; use a map if hundreds become normal.
        for (self.bindings.items) |item|
            if (std.mem.eql(u8, item.name, name)) return item;
        return null;
    }
};

pub const Call = struct {
    gpa: std.mem.Allocator,
    arguments: []const []const u8,
    response: std.ArrayList(u8) = .empty,

    fn deinit(self: *Call) void {
        self.response.deinit(self.gpa);
    }

    pub fn bytes(self: *const Call, index: usize) ![]const u8 {
        if (index >= self.arguments.len) return error.MissingArgument;
        return self.arguments[index];
    }

    pub fn string(self: *const Call, index: usize) ![]const u8 {
        const value = try self.bytes(index);
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        return value;
    }

    pub fn int(self: *const Call, index: usize) !i64 {
        return std.fmt.parseInt(i64, try self.string(index), 10);
    }

    pub fn boolean(self: *const Call, index: usize) !bool {
        const value = try self.string(index);
        if (std.mem.eql(u8, value, "true")) return true;
        if (std.mem.eql(u8, value, "false")) return false;
        return error.InvalidBoolean;
    }

    pub fn reply(self: *Call, value: []const u8) !void {
        self.response.clearRetainingCapacity();
        try self.response.appendSlice(self.gpa, value);
    }

    pub fn replyInt(self: *Call, value: anytype) !void {
        var buffer: [64]u8 = undefined;
        try self.reply(try std.fmt.bufPrint(&buffer, "{d}", .{value}));
    }
};

pub const Window = struct {
    state: *WindowState,

    pub fn bind(
        self: Window,
        name: []const u8,
        handler: Handler,
        user_data: ?*anyopaque,
    ) !void {
        if (name.len == 0 or std.mem.indexOfScalar(u8, name, 0) != null)
            return error.InvalidBindingName;
        for (self.state.bindings.items) |*binding| {
            if (std.mem.eql(u8, binding.name, name)) {
                binding.handler = handler;
                binding.user_data = user_data;
                return;
            }
        }
        try self.state.bindings.append(self.state.gpa, .{
            .name = try self.state.gpa.dupe(u8, name),
            .handler = handler,
            .user_data = user_data,
        });
    }

    pub fn open(self: Window, io: std.Io, running: *const Running) !void {
        if (self.state != running.app.window) return error.UnknownWindow;
        const url = try running.url(self.state.gpa);
        defer self.state.gpa.free(url);
        try browser.open(self.state.gpa, io, url);
    }
};

pub const App = struct {
    gpa: std.mem.Allocator,
    options: Options,
    window: ?*WindowState = null,
    server: ?Linsang.Server = null,
    started: bool = false,
    closed: std.atomic.Value(bool) = .init(false),

    pub const Options = struct {
        address: []const u8 = "127.0.0.1",
        port: u16 = 0,
    };

    pub const WindowOptions = struct {
        html: []const u8,
    };

    pub fn init(gpa: std.mem.Allocator, options: Options) App {
        return .{ .gpa = gpa, .options = options };
    }

    pub fn deinit(self: *App) void {
        std.debug.assert(!self.started);
        if (self.window) |window| window.deinit();
        self.* = undefined;
    }

    pub fn createWindow(self: *App, options: WindowOptions) !Window {
        if (self.started) return error.AlreadyStarted;
        // ponytail: phase 1 supports one window; replace with a map in phase 3.
        if (self.window != null) return error.OneWindowOnly;
        const state = try self.gpa.create(WindowState);
        errdefer self.gpa.destroy(state);
        state.* = .{
            .gpa = self.gpa,
            .html = try self.gpa.dupe(u8, options.html),
        };
        self.window = state;
        return .{ .state = state };
    }

    pub fn start(self: *App, io: std.Io) !Running {
        if (self.started) return error.AlreadyStarted;
        const window = self.window orelse return error.NoWindow;
        var token_bytes: [4]u8 = undefined;
        io.random(&token_bytes);
        window.token = std.mem.readInt(u32, &token_bytes, .little);
        if (window.token == 0) window.token = 1;
        self.closed.store(false, .release);
        self.server = Linsang.Server.init(self.gpa, .{
            .address = self.options.address,
            .port = self.options.port,
            .on_request = onRequest,
            .on_ws_message = onMessage,
            .on_ws_close = onClose,
            .user_data = self,
        });
        errdefer self.server = null;
        const inner = try self.server.?.start(io);
        self.started = true;
        return .{ .app = self, .inner = inner };
    }
};

pub const Running = struct {
    app: *App,
    inner: Linsang.server.Running,
    stopped: bool = false,

    pub fn url(self: *const Running, gpa: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(gpa, "http://{s}:{d}/", .{
            self.app.options.address,
            self.inner.address.getPort(),
        });
    }

    pub fn stop(self: *Running) !void {
        if (self.stopped) return;
        try self.inner.stop();
        self.stopped = true;
        self.app.started = false;
        self.app.server = null;
    }

    pub fn wait(self: *Running) !void {
        // ponytail: one-window polling is enough; use a condition for multi-window.
        while (!self.app.closed.load(.acquire))
            try std.Io.sleep(self.inner.io, .fromMilliseconds(10), .awake);
        try self.stop();
    }
};

fn appFrom(user_data: ?*anyopaque) *App {
    return @ptrCast(@alignCast(user_data.?));
}

fn failResponse(response: *Linsang.Response) Linsang.Action {
    response.reset();
    response.status = .internal_server_error;
    return .respond;
}

fn onRequest(
    request: *const Linsang.Request,
    response: *Linsang.Response,
    user_data: ?*anyopaque,
) Linsang.Action {
    const app = appFrom(user_data);
    const window = app.window.?;
    if (std.mem.eql(u8, request.path, "/_webui_ws_connect")) return .upgrade;
    if (std.mem.eql(u8, request.path, "/")) {
        response.setHeader("Content-Type", "text/html; charset=utf-8") catch
            return failResponse(response);
        response.write(window.html) catch return failResponse(response);
        return .respond;
    }
    if (std.mem.eql(u8, request.path, "/webui.js")) {
        response.setHeader("Content-Type", "text/javascript; charset=utf-8") catch
            return failResponse(response);
        response.print("globalThis.__zigWebuiToken={d};\n", .{window.token}) catch
            return failResponse(response);
        response.write(bridge) catch return failResponse(response);
        return .respond;
    }
    response.status = .not_found;
    return .respond;
}

fn send(
    connection: *Linsang.Connection,
    gpa: std.mem.Allocator,
    header: protocol.Header,
    payload: []const u8,
) !void {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try protocol.append(&bytes, gpa, header, payload);
    try connection.sendBinary(bytes.items);
}

fn onMessage(
    connection: *Linsang.Connection,
    message: Linsang.websocket.Message,
    user_data: ?*anyopaque,
) void {
    if (message.opcode != .binary) {
        connection.wsClose(.unsupported_data, "");
        return;
    }
    const app = appFrom(user_data);
    const window = app.window.?;
    const packet = protocol.decode(message.data) catch {
        connection.wsClose(.protocol_error, "");
        return;
    };
    if (packet.header.token != window.token) {
        if (packet.header.command == .check_token)
            send(connection, app.gpa, packet.header, &.{0}) catch {}
        else
            connection.wsClose(.policy_violation, "");
        return;
    }

    switch (packet.header.command) {
        .check_token => send(connection, app.gpa, packet.header, &.{1}) catch {},
        .call => {
            const decoded = protocol.decodeCall(packet.payload) catch {
                connection.wsClose(.protocol_error, "");
                return;
            };
            const binding = window.binding(decoded.name) orelse {
                send(connection, app.gpa, packet.header, "") catch {};
                return;
            };
            var call: Call = .{
                .gpa = app.gpa,
                .arguments = decoded.slice(),
            };
            defer call.deinit();
            binding.handler(&call, binding.user_data) catch {
                call.reply("") catch {};
            };
            send(connection, app.gpa, packet.header, call.response.items) catch {};
        },
        else => connection.wsClose(.unsupported_data, ""),
    }
}

fn onClose(_: *Linsang.Connection, user_data: ?*anyopaque) void {
    appFrom(user_data).closed.store(true, .release);
}

test "call accessors and one-window lifecycle" {
    const gpa = std.testing.allocator;
    var app = App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{ .html = "hello" });
    try std.testing.expectError(
        error.OneWindowOnly,
        app.createWindow(.{ .html = "again" }),
    );

    var call: Call = .{
        .gpa = gpa,
        .arguments = &.{ "42", "true" },
    };
    defer call.deinit();
    try std.testing.expectEqual(@as(i64, 42), try call.int(0));
    try std.testing.expect(try call.boolean(1));
    try call.replyInt(84);
    try std.testing.expectEqualStrings("84", call.response.items);
    _ = window;
}

fn integrationHandler(call: *Call, _: ?*anyopaque) !void {
    if (!std.mem.eql(u8, try call.string(0), "Zig"))
        return error.UnexpectedArgument;
    try call.reply("Hello from Zig");
}

fn writeAll(stream: std.Io.net.Stream, io: std.Io, bytes: []const u8) !void {
    var buffer: [512]u8 = undefined;
    var writer = stream.writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn readExact(stream: std.Io.net.Stream, io: std.Io, bytes: []u8) !void {
    var at: usize = 0;
    while (at < bytes.len) {
        var parts = [1][]u8{bytes[at..]};
        const count = try io.vtable.netRead(io.userdata, stream.socket.handle, &parts);
        if (count == 0) return error.EndOfStream;
        at += count;
    }
}

fn readUntil(
    stream: std.Io.net.Stream,
    io: std.Io,
    buffer: []u8,
    needle: []const u8,
) ![]u8 {
    var len: usize = 0;
    while (std.mem.indexOf(u8, buffer[0..len], needle) == null) {
        if (len == buffer.len) return error.StreamTooLong;
        var parts = [1][]u8{buffer[len..]};
        const count = try io.vtable.netRead(io.userdata, stream.socket.handle, &parts);
        if (count == 0) break;
        len += count;
    }
    return buffer[0..len];
}

fn sendClientFrame(
    stream: std.Io.net.Stream,
    io: std.Io,
    payload: []const u8,
) !void {
    if (payload.len > 125) return error.TestPayloadTooLarge;
    var frame: [131]u8 = undefined;
    const mask = [4]u8{ 1, 2, 3, 4 };
    frame[0] = 0x82;
    frame[1] = 0x80 | @as(u8, @intCast(payload.len));
    @memcpy(frame[2..6], &mask);
    for (payload, 0..) |byte, index| frame[6 + index] = byte ^ mask[index & 3];
    try writeAll(stream, io, frame[0 .. payload.len + 6]);
}

fn readServerFrame(
    stream: std.Io.net.Stream,
    io: std.Io,
    buffer: []u8,
) ![]u8 {
    var header: [2]u8 = undefined;
    try readExact(stream, io, &header);
    if (header[0] != 0x82 or header[1] >= 126 or header[1] > buffer.len)
        return error.InvalidServerFrame;
    try readExact(stream, io, buffer[0..header[1]]);
    return buffer[0..header[1]];
}

test "embedded page and JS to Zig call complete over HTTP and WebSocket" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{ .async_limit = .unlimited });
    defer threaded.deinit();
    const io = threaded.io();

    var app = App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{ .html = "test page" });
    try window.bind("greet", integrationHandler, null);
    var running = try app.start(io);
    defer running.stop() catch {};

    {
        const client = try running.inner.address.connect(io, .{ .mode = .stream });
        defer client.close(io);
        try writeAll(
            client,
            io,
            "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n",
        );
        var response: [512]u8 = undefined;
        const bytes = try readUntil(client, io, &response, "test page");
        try std.testing.expect(std.mem.indexOf(u8, bytes, "HTTP/1.1 200 OK") != null);
    }

    const client = try running.inner.address.connect(io, .{ .mode = .stream });
    defer client.close(io);
    try writeAll(
        client,
        io,
        "GET /_webui_ws_connect HTTP/1.1\r\nHost: localhost\r\n" ++
            "Upgrade: websocket\r\nConnection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n\r\n",
    );
    var handshake: [512]u8 = undefined;
    const accepted = try readUntil(client, io, &handshake, "\r\n\r\n");
    try std.testing.expect(std.mem.startsWith(u8, accepted, "HTTP/1.1 101"));

    var packet: std.ArrayList(u8) = .empty;
    defer packet.deinit(gpa);
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .command = .check_token,
    }, "");
    try sendClientFrame(client, io, packet.items);
    var response_payload: [125]u8 = undefined;
    const checked = try readServerFrame(client, io, &response_payload);
    const check_packet = try protocol.decode(checked);
    try std.testing.expectEqualSlices(u8, &.{1}, check_packet.payload);

    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = 9,
        .command = .call,
    }, "greet\x003\x00Zig\x00");
    try sendClientFrame(client, io, packet.items);
    const replied = try readServerFrame(client, io, &response_payload);
    const reply_packet = try protocol.decode(replied);
    try std.testing.expectEqual(@as(u16, 9), reply_packet.header.id);
    try std.testing.expectEqualStrings("Hello from Zig", reply_packet.payload);

    try client.shutdown(io, .both);
    try running.wait();
}
