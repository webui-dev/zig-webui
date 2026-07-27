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

pub const EvalResult = union(enum) {
    value: []const u8,
    javascript_error: []const u8,
};

const EvalStatus = enum {
    waiting,
    value,
    javascript_error,
    result_too_large,
    disconnected,
};

const PendingEval = struct {
    id: u16,
    buffer: []u8,
    len: usize = 0,
    status: EvalStatus = .waiting,
    done: std.Io.Event = .unset,
};

const WindowState = struct {
    gpa: std.mem.Allocator,
    html: []u8,
    token: u32 = 0,
    bindings: std.ArrayList(Binding) = .empty,
    mutex: std.Io.Mutex = .init,
    eval_mutex: std.Io.Mutex = .init,
    peer: ?Linsang.WebSocketPeer = null,
    peer_key: usize = 0,
    next_eval_id: u16 = 1,
    pending_eval: ?PendingEval = null,

    fn deinit(self: *WindowState) void {
        std.debug.assert(self.pending_eval == null);
        if (self.peer) |*peer| peer.deinit();
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

    fn authenticate(self: *WindowState, connection: *Linsang.Connection) !void {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const key = @intFromPtr(connection);
        if (self.peer) |_| {
            if (self.peer_key == key) return;
            return error.ClientAlreadyConnected;
        }
        self.peer = try connection.peer();
        self.peer_key = key;
    }

    fn isClient(self: *WindowState, connection: *Linsang.Connection) bool {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        return self.peer != null and self.peer_key == @intFromPtr(connection);
    }

    fn disconnected(self: *WindowState, connection: *Linsang.Connection) bool {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        if (self.peer == null or self.peer_key != @intFromPtr(connection))
            return false;
        self.peer.?.deinit();
        self.peer = null;
        self.peer_key = 0;
        if (self.pending_eval) |*pending| {
            pending.status = .disconnected;
            pending.done.set(connection.io);
        }
        return true;
    }

    fn finishEval(
        self: *WindowState,
        connection: *Linsang.Connection,
        id: u16,
        payload: []const u8,
    ) !void {
        if (payload.len < 1) return error.InvalidPacket;
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        if (self.peer_key != @intFromPtr(connection)) return;
        const pending = if (self.pending_eval) |*pending| pending else return;
        if (pending.id != id or pending.status != .waiting) return;

        var value = payload[1..];
        if (value.len > 0 and value[value.len - 1] == 0)
            value = value[0 .. value.len - 1];
        if (value.len > pending.buffer.len) {
            pending.status = .result_too_large;
        } else {
            @memcpy(pending.buffer[0..value.len], value);
            pending.len = value.len;
            pending.status = if (payload[0] == 0) .value else .javascript_error;
        }
        pending.done.set(connection.io);
    }

    fn cancelEval(self: *WindowState, io: std.Io, id: u16) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.pending_eval) |pending| {
            if (pending.id == id) self.pending_eval = null;
        }
    }

    fn takeEval(self: *WindowState, io: std.Io, id: u16) !EvalResult {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const pending = self.pending_eval orelse return error.ConnectionClosed;
        if (pending.id != id) return error.ConnectionClosed;
        self.pending_eval = null;
        const value = pending.buffer[0..pending.len];
        return switch (pending.status) {
            .value => .{ .value = value },
            .javascript_error => .{ .javascript_error = value },
            .result_too_large => error.ResultTooLarge,
            .disconnected => error.ConnectionClosed,
            .waiting => error.Timeout,
        };
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

    pub fn eval(
        self: Window,
        io: std.Io,
        script: []const u8,
        result_buffer: []u8,
        timeout: std.Io.Duration,
    ) !EvalResult {
        if (!std.unicode.utf8ValidateSlice(script)) return error.InvalidUtf8;
        if (!self.state.eval_mutex.tryLock()) return error.Busy;
        defer self.state.eval_mutex.unlock(io);

        const deadline = std.Io.Clock.Timestamp.fromNow(io, .{
            .clock = .awake,
            .raw = timeout,
        });
        var peer: Linsang.WebSocketPeer = while (true) {
            self.state.mutex.lockUncancelable(io);
            if (self.state.peer) |stored| {
                const owned = stored.clone();
                self.state.mutex.unlock(io);
                break owned;
            }
            self.state.mutex.unlock(io);
            if (deadline.compare(.lte, .now(io, .awake))) return error.Timeout;
            // ponytail: phase 2 has one client; replace polling with an event
            // when reconnecting clients are supported.
            try std.Io.sleep(io, .fromMilliseconds(1), .awake);
        };
        defer peer.deinit();

        self.state.mutex.lockUncancelable(io);
        const id = self.state.next_eval_id;
        self.state.next_eval_id +%= 1;
        if (self.state.next_eval_id == 0) self.state.next_eval_id = 1;
        self.state.pending_eval = .{ .id = id, .buffer = result_buffer };
        const done = &self.state.pending_eval.?.done;
        self.state.mutex.unlock(io);
        errdefer self.state.cancelEval(io, id);

        var packet: std.ArrayList(u8) = .empty;
        defer packet.deinit(self.state.gpa);
        try protocol.append(&packet, self.state.gpa, .{
            .token = self.state.token,
            .id = id,
            .command = .js,
        }, script);
        peer.sendBinary(packet.items) catch |err| switch (err) {
            error.Closed => return error.ConnectionClosed,
            else => return err,
        };

        while (true) {
            done.waitTimeout(io, .{ .deadline = deadline }) catch |wait_error| {
                self.state.mutex.lockUncancelable(io);
                const still_waiting = if (self.state.pending_eval) |pending|
                    pending.id == id and pending.status == .waiting
                else
                    false;
                self.state.mutex.unlock(io);
                if (!still_waiting) break;
                if (wait_error == error.Canceled) return wait_error;
                if (deadline.compare(.lte, .now(io, .awake))) return error.Timeout;
                continue;
            };
            break;
        }
        return self.state.takeEval(io, id);
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
            .ws_idle_timeout = null,
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
        .check_token => {
            window.authenticate(connection) catch {
                send(connection, app.gpa, packet.header, &.{0}) catch {};
                connection.wsClose(.policy_violation, "");
                return;
            };
            send(connection, app.gpa, packet.header, &.{1}) catch {};
        },
        .js => window.finishEval(
            connection,
            packet.header.id,
            packet.payload,
        ) catch connection.wsClose(.protocol_error, ""),
        .call => {
            if (!window.isClient(connection)) {
                connection.wsClose(.policy_violation, "");
                return;
            }
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

fn onClose(connection: *Linsang.Connection, user_data: ?*anyopaque) void {
    const app = appFrom(user_data);
    if (app.window.?.disconnected(connection))
        app.closed.store(true, .release);
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

test "JavaScript and Zig calls complete over HTTP and WebSocket" {
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

    var eval_buffer: [64]u8 = undefined;
    var eval_future = io.async(Window.eval, .{
        window,
        io,
        "return 6 * 7",
        &eval_buffer,
        std.Io.Duration.fromSeconds(1),
    });
    const eval_request = try protocol.decode(try readServerFrame(
        client,
        io,
        &response_payload,
    ));
    try std.testing.expectEqual(protocol.Command.js, eval_request.header.command);
    try std.testing.expectEqualStrings("return 6 * 7", eval_request.payload);
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = eval_request.header.id,
        .command = .js,
    }, "\x0042\x00");
    try sendClientFrame(client, io, packet.items);
    switch (try eval_future.await(io)) {
        .value => |value| try std.testing.expectEqualStrings("42", value),
        .javascript_error => return error.UnexpectedJavaScriptError,
    }

    var error_future = io.async(Window.eval, .{
        window,
        io,
        "throw new Error('nope')",
        &eval_buffer,
        std.Io.Duration.fromSeconds(1),
    });
    const error_request = try protocol.decode(try readServerFrame(
        client,
        io,
        &response_payload,
    ));
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = error_request.header.id,
        .command = .js,
    }, "\x01nope\x00");
    try sendClientFrame(client, io, packet.items);
    switch (try error_future.await(io)) {
        .value => return error.ExpectedJavaScriptError,
        .javascript_error => |message| try std.testing.expectEqualStrings("nope", message),
    }

    var timeout_future = io.async(Window.eval, .{
        window,
        io,
        "return 'late'",
        &eval_buffer,
        std.Io.Duration.fromMilliseconds(10),
    });
    _ = try readServerFrame(client, io, &response_payload);
    try std.testing.expectError(error.Timeout, timeout_future.await(io));

    var disconnect_future = io.async(Window.eval, .{
        window,
        io,
        "return 'never'",
        &eval_buffer,
        std.Io.Duration.fromSeconds(1),
    });
    _ = try readServerFrame(client, io, &response_payload);
    try client.shutdown(io, .both);
    try std.testing.expectError(error.ConnectionClosed, disconnect_future.await(io));
    try running.wait();
}
