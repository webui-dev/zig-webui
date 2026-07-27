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
    client_id: u64,
    buffer: []u8,
    len: usize = 0,
    status: EvalStatus = .waiting,
    done: std.Io.Event = .unset,
};

const ConnectedClient = struct {
    id: u64,
    key: usize,
    peer: Linsang.WebSocketPeer,
};

const WindowState = struct {
    gpa: std.mem.Allocator,
    html: []u8,
    max_clients: usize,
    token: u32 = 0,
    bindings: std.ArrayList(Binding) = .empty,
    mutex: std.Io.Mutex = .init,
    eval_mutex: std.Io.Mutex = .init,
    clients: std.ArrayList(ConnectedClient) = .empty,
    next_client_id: u64 = 1,
    next_eval_id: u16 = 1,
    pending_eval: ?PendingEval = null,

    fn deinit(self: *WindowState) void {
        std.debug.assert(self.pending_eval == null);
        for (self.clients.items) |*connected| connected.peer.deinit();
        self.clients.deinit(self.gpa);
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

    fn clientIndexById(self: *WindowState, id: u64) ?usize {
        // ponytail: max_clients is bounded and small; use a map if limits grow.
        for (self.clients.items, 0..) |connected, index|
            if (connected.id == id) return index;
        return null;
    }

    fn clientIndexByKey(self: *WindowState, key: usize) ?usize {
        for (self.clients.items, 0..) |connected, index|
            if (connected.key == key) return index;
        return null;
    }

    fn authenticate(self: *WindowState, connection: *Linsang.Connection) !void {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const key = @intFromPtr(connection);
        if (self.clientIndexByKey(key) != null) return;
        if (self.clients.items.len >= self.max_clients)
            return error.ClientLimitReached;

        var peer = try connection.peer();
        errdefer peer.deinit();
        try self.clients.append(self.gpa, .{
            .id = self.next_client_id,
            .key = key,
            .peer = peer,
        });
        self.next_client_id +%= 1;
        if (self.next_client_id == 0) self.next_client_id = 1;
    }

    fn client(self: *WindowState, connection: *Linsang.Connection) ?Client {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const index = self.clientIndexByKey(@intFromPtr(connection)) orelse
            return null;
        return .{ .state = self, .client_id = self.clients.items[index].id };
    }

    fn disconnected(self: *WindowState, connection: *Linsang.Connection) bool {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const index = self.clientIndexByKey(@intFromPtr(connection)) orelse
            return false;
        var disconnected_client = self.clients.swapRemove(index);
        disconnected_client.peer.deinit();
        if (self.pending_eval) |*pending| {
            if (pending.client_id == disconnected_client.id) {
                pending.status = .disconnected;
                pending.done.set(connection.io);
            }
        }
        return self.clients.items.len == 0;
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
        const client_index = self.clientIndexByKey(@intFromPtr(connection)) orelse
            return;
        const client_id = self.clients.items[client_index].id;
        const pending = if (self.pending_eval) |*pending| pending else return;
        if (pending.id != id or
            pending.client_id != client_id or
            pending.status != .waiting) return;

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

    fn eval(
        self: *WindowState,
        io: std.Io,
        target_client_id: ?u64,
        script: []const u8,
        result_buffer: []u8,
        timeout: std.Io.Duration,
    ) !EvalResult {
        if (!std.unicode.utf8ValidateSlice(script)) return error.InvalidUtf8;
        if (!self.eval_mutex.tryLock()) return error.Busy;
        defer self.eval_mutex.unlock(io);

        const deadline = std.Io.Clock.Timestamp.fromNow(io, .{
            .clock = .awake,
            .raw = timeout,
        });
        var client_id: u64 = undefined;
        var peer: Linsang.WebSocketPeer = while (true) {
            self.mutex.lockUncancelable(io);
            if (target_client_id) |target| {
                if (self.clientIndexById(target)) |index| {
                    client_id = target;
                    const owned = self.clients.items[index].peer.clone();
                    self.mutex.unlock(io);
                    break owned;
                }
                self.mutex.unlock(io);
                return error.ConnectionClosed;
            }
            if (self.clients.items.len == 1) {
                client_id = self.clients.items[0].id;
                const owned = self.clients.items[0].peer.clone();
                self.mutex.unlock(io);
                break owned;
            }
            if (self.clients.items.len > 1) {
                self.mutex.unlock(io);
                return error.MultipleClientsConnected;
            }
            self.mutex.unlock(io);
            if (deadline.compare(.lte, .now(io, .awake))) return error.Timeout;
            // ponytail: polling is enough while one window owns the server;
            // replace it with an event when multiple windows are supported.
            try std.Io.sleep(io, .fromMilliseconds(1), .awake);
        };
        defer peer.deinit();

        self.mutex.lockUncancelable(io);
        const id = self.next_eval_id;
        self.next_eval_id +%= 1;
        if (self.next_eval_id == 0) self.next_eval_id = 1;
        self.pending_eval = .{
            .id = id,
            .client_id = client_id,
            .buffer = result_buffer,
        };
        const done = &self.pending_eval.?.done;
        self.mutex.unlock(io);
        errdefer self.cancelEval(io, id);

        var packet: std.ArrayList(u8) = .empty;
        defer packet.deinit(self.gpa);
        try protocol.append(&packet, self.gpa, .{
            .token = self.token,
            .id = id,
            .command = .js,
        }, script);
        peer.sendBinary(packet.items) catch |err| switch (err) {
            error.Closed => return error.ConnectionClosed,
            else => return err,
        };

        while (true) {
            done.waitTimeout(io, .{ .deadline = deadline }) catch |wait_error| {
                self.mutex.lockUncancelable(io);
                const still_waiting = if (self.pending_eval) |pending|
                    pending.id == id and pending.status == .waiting
                else
                    false;
                self.mutex.unlock(io);
                if (!still_waiting) break;
                if (wait_error == error.Canceled) return wait_error;
                if (deadline.compare(.lte, .now(io, .awake)))
                    return error.Timeout;
                continue;
            };
            break;
        }
        return self.takeEval(io, id);
    }
};

pub const Call = struct {
    gpa: std.mem.Allocator,
    client: Client,
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

pub const Client = struct {
    state: *WindowState,
    client_id: u64,

    fn send(
        self: Client,
        io: std.Io,
        command: protocol.Command,
        payload: []const u8,
    ) !void {
        self.state.mutex.lockUncancelable(io);
        const index = self.state.clientIndexById(self.client_id) orelse {
            self.state.mutex.unlock(io);
            return error.ConnectionClosed;
        };
        var peer = self.state.clients.items[index].peer.clone();
        self.state.mutex.unlock(io);
        defer peer.deinit();

        var packet: std.ArrayList(u8) = .empty;
        defer packet.deinit(self.state.gpa);
        try protocol.append(&packet, self.state.gpa, .{
            .token = self.state.token,
            .command = command,
        }, payload);
        peer.sendBinary(packet.items) catch |err| switch (err) {
            error.Closed => return error.ConnectionClosed,
            else => return err,
        };
    }

    pub fn id(self: Client) u64 {
        return self.client_id;
    }

    pub fn isConnected(self: Client, io: std.Io) bool {
        self.state.mutex.lockUncancelable(io);
        defer self.state.mutex.unlock(io);
        return self.state.clientIndexById(self.client_id) != null;
    }

    pub fn eval(
        self: Client,
        io: std.Io,
        script: []const u8,
        result_buffer: []u8,
        timeout: std.Io.Duration,
    ) !EvalResult {
        return self.state.eval(
            io,
            self.client_id,
            script,
            result_buffer,
            timeout,
        );
    }

    pub fn navigate(self: Client, io: std.Io, url: []const u8) !void {
        if (url.len == 0 or std.mem.indexOfScalar(u8, url, 0) != null)
            return error.InvalidUrl;
        if (!std.unicode.utf8ValidateSlice(url)) return error.InvalidUtf8;
        try self.send(io, .navigation, url);
    }

    pub fn close(self: Client, io: std.Io) !void {
        try self.send(io, .close, "");
    }

    pub fn sendRaw(
        self: Client,
        io: std.Io,
        function: []const u8,
        data: []const u8,
    ) !void {
        if (function.len == 0 or
            std.mem.indexOfScalar(u8, function, 0) != null)
        {
            return error.InvalidFunctionName;
        }
        if (!std.unicode.utf8ValidateSlice(function)) return error.InvalidUtf8;

        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.state.gpa);
        try payload.appendSlice(self.state.gpa, function);
        try payload.append(self.state.gpa, 0);
        try payload.appendSlice(self.state.gpa, data);
        try self.send(io, .raw, payload.items);
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
        return self.state.eval(io, null, script, result_buffer, timeout);
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
        /// One client by default; values above one explicitly enable
        /// bounded multi-client mode.
        max_clients: usize = 1,
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
        if (options.max_clients == 0) return error.InvalidClientLimit;
        // ponytail: phase 1 supports one window; replace with a map in phase 3.
        if (self.window != null) return error.OneWindowOnly;
        const state = try self.gpa.create(WindowState);
        errdefer self.gpa.destroy(state);
        state.* = .{
            .gpa = self.gpa,
            .html = try self.gpa.dupe(u8, options.html),
            .max_clients = options.max_clients,
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
            const client = window.client(connection) orelse {
                connection.wsClose(.policy_violation, "");
                return;
            };
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
                .client = client,
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
    var invalid_app = App.init(gpa, .{});
    defer invalid_app.deinit();
    try std.testing.expectError(
        error.InvalidClientLimit,
        invalid_app.createWindow(.{ .html = "invalid", .max_clients = 0 }),
    );

    var app = App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{ .html = "hello" });
    try std.testing.expectError(
        error.OneWindowOnly,
        app.createWindow(.{ .html = "again" }),
    );

    var call: Call = .{
        .gpa = gpa,
        .client = .{ .state = window.state, .client_id = 1 },
        .arguments = &.{ "42", "true" },
    };
    defer call.deinit();
    try std.testing.expectEqual(@as(i64, 42), try call.int(0));
    try std.testing.expect(try call.boolean(1));
    try call.replyInt(84);
    try std.testing.expectEqualStrings("84", call.response.items);
}

fn integrationHandler(call: *Call, user_data: ?*anyopaque) !void {
    if (!std.mem.eql(u8, try call.string(0), "Zig"))
        return error.UnexpectedArgument;
    const client_id: *std.atomic.Value(u64) =
        @ptrCast(@alignCast(user_data.?));
    client_id.store(call.client.id(), .release);
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

fn connectTestWebSocket(
    address: std.Io.net.IpAddress,
    io: std.Io,
) !std.Io.net.Stream {
    const stream = try address.connect(io, .{ .mode = .stream });
    errdefer stream.close(io);
    try writeAll(
        stream,
        io,
        "GET /_webui_ws_connect HTTP/1.1\r\nHost: localhost\r\n" ++
            "Upgrade: websocket\r\nConnection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
            "Sec-WebSocket-Version: 13\r\n\r\n",
    );
    var handshake: [512]u8 = undefined;
    const accepted = try readUntil(stream, io, &handshake, "\r\n\r\n");
    if (!std.mem.startsWith(u8, accepted, "HTTP/1.1 101"))
        return error.WebSocketUpgradeFailed;
    return stream;
}

fn authenticateTestClient(
    stream: std.Io.net.Stream,
    io: std.Io,
    gpa: std.mem.Allocator,
    token: u32,
    response_buffer: []u8,
) !bool {
    var packet: std.ArrayList(u8) = .empty;
    defer packet.deinit(gpa);
    try protocol.append(&packet, gpa, .{
        .token = token,
        .command = .check_token,
    }, "");
    try sendClientFrame(stream, io, packet.items);
    const response = try protocol.decode(try readServerFrame(
        stream,
        io,
        response_buffer,
    ));
    return std.mem.eql(u8, response.payload, &.{1});
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
    var called_client_id: std.atomic.Value(u64) = .init(0);
    try window.bind("greet", integrationHandler, &called_client_id);
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

    const client = try connectTestWebSocket(running.inner.address, io);
    defer client.close(io);
    var response_payload: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        client,
        io,
        gpa,
        window.state.token,
        &response_payload,
    ));
    {
        const rejected = try connectTestWebSocket(running.inner.address, io);
        defer rejected.close(io);
        var rejected_payload: [125]u8 = undefined;
        try std.testing.expect(!try authenticateTestClient(
            rejected,
            io,
            gpa,
            window.state.token,
            &rejected_payload,
        ));
    }

    var packet: std.ArrayList(u8) = .empty;
    defer packet.deinit(gpa);
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
    const targeted_client: Client = .{
        .state = window.state,
        .client_id = called_client_id.load(.acquire),
    };
    try std.testing.expect(targeted_client.id() != 0);
    try std.testing.expect(targeted_client.isConnected(io));

    var eval_buffer: [64]u8 = undefined;
    var eval_future = io.async(Client.eval, .{
        targeted_client,
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

    try std.testing.expectError(
        error.InvalidUrl,
        targeted_client.navigate(io, ""),
    );
    try targeted_client.navigate(io, "/next");
    const navigation = try protocol.decode(try readServerFrame(
        client,
        io,
        &response_payload,
    ));
    try std.testing.expectEqual(
        protocol.Command.navigation,
        navigation.header.command,
    );
    try std.testing.expectEqualStrings("/next", navigation.payload);

    try std.testing.expectError(
        error.InvalidFunctionName,
        targeted_client.sendRaw(io, "", ""),
    );
    const raw_data = [_]u8{ 0, 1, 255 };
    try targeted_client.sendRaw(io, "receiveRaw", &raw_data);
    const raw = try protocol.decode(try readServerFrame(
        client,
        io,
        &response_payload,
    ));
    try std.testing.expectEqual(protocol.Command.raw, raw.header.command);
    try std.testing.expectEqualStrings("receiveRaw", raw.payload[0..10]);
    try std.testing.expectEqual(@as(u8, 0), raw.payload[10]);
    try std.testing.expectEqualSlices(u8, &raw_data, raw.payload[11..]);

    try targeted_client.close(io);
    const close = try protocol.decode(try readServerFrame(
        client,
        io,
        &response_payload,
    ));
    try std.testing.expectEqual(protocol.Command.close, close.header.command);
    try std.testing.expectEqual(@as(usize, 0), close.payload.len);

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
    try std.testing.expect(!targeted_client.isConnected(io));
    try std.testing.expectError(error.ConnectionClosed, targeted_client.eval(
        io,
        "return 'stale'",
        &eval_buffer,
        std.Io.Duration.fromSeconds(1),
    ));
    try std.testing.expectError(
        error.ConnectionClosed,
        targeted_client.close(io),
    );
    try running.wait();
}

test "multi-client limits, targeting, and disconnect lifecycle" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var threaded = std.Io.Threaded.init(gpa, .{ .async_limit = .unlimited });
    defer threaded.deinit();
    const io = threaded.io();

    var app = App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{
        .html = "multi-client test",
        .max_clients = 2,
    });
    var called_client_id: std.atomic.Value(u64) = .init(0);
    try window.bind("greet", integrationHandler, &called_client_id);
    var running = try app.start(io);
    defer running.stop() catch {};

    const first_stream = try connectTestWebSocket(running.inner.address, io);
    defer first_stream.close(io);
    var first_response: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        first_stream,
        io,
        gpa,
        window.state.token,
        &first_response,
    ));

    var packet: std.ArrayList(u8) = .empty;
    defer packet.deinit(gpa);
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = 1,
        .command = .call,
    }, "greet\x003\x00Zig\x00");
    try sendClientFrame(first_stream, io, packet.items);
    const first_reply = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    try std.testing.expectEqualStrings("Hello from Zig", first_reply.payload);
    const first = Client{
        .state = window.state,
        .client_id = called_client_id.load(.acquire),
    };

    const second_stream = try connectTestWebSocket(running.inner.address, io);
    defer second_stream.close(io);
    var second_response: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        second_stream,
        io,
        gpa,
        window.state.token,
        &second_response,
    ));
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = 2,
        .command = .call,
    }, "greet\x003\x00Zig\x00");
    try sendClientFrame(second_stream, io, packet.items);
    const second_reply = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqualStrings("Hello from Zig", second_reply.payload);
    const second = Client{
        .state = window.state,
        .client_id = called_client_id.load(.acquire),
    };
    try std.testing.expect(first.id() != second.id());

    {
        const rejected = try connectTestWebSocket(running.inner.address, io);
        defer rejected.close(io);
        var rejected_response: [125]u8 = undefined;
        try std.testing.expect(!try authenticateTestClient(
            rejected,
            io,
            gpa,
            window.state.token,
            &rejected_response,
        ));
    }

    var eval_buffer: [16]u8 = undefined;
    try std.testing.expectError(error.MultipleClientsConnected, window.eval(
        io,
        "return 1",
        &eval_buffer,
        .fromSeconds(1),
    ));

    try first.navigate(io, "/first");
    const raw_data = [_]u8{ 2, 3, 5 };
    try second.sendRaw(io, "receiveRaw", &raw_data);
    const first_targeted = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    try std.testing.expectEqual(
        protocol.Command.navigation,
        first_targeted.header.command,
    );
    try std.testing.expectEqualStrings("/first", first_targeted.payload);
    const second_targeted = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(protocol.Command.raw, second_targeted.header.command);

    try first.close(io);
    const first_close = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    try std.testing.expectEqual(protocol.Command.close, first_close.header.command);
    try second.navigate(io, "/second");
    const second_navigation = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(
        protocol.Command.navigation,
        second_navigation.header.command,
    );
    try std.testing.expectEqualStrings("/second", second_navigation.payload);

    var targeted_eval_buffer: [16]u8 = undefined;
    var targeted_eval = io.async(Client.eval, .{
        second,
        io,
        "return 7",
        &targeted_eval_buffer,
        std.Io.Duration.fromSeconds(1),
    });
    const targeted_eval_request = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(
        protocol.Command.js,
        targeted_eval_request.header.command,
    );

    try first_stream.shutdown(io, .both);
    var first_disconnected = false;
    for (0..100) |_| {
        if (!first.isConnected(io)) {
            first_disconnected = true;
            break;
        }
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    try std.testing.expect(first_disconnected);
    try std.testing.expect(second.isConnected(io));
    try std.testing.expect(!app.closed.load(.acquire));

    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = targeted_eval_request.header.id,
        .command = .js,
    }, "\x007\x00");
    try sendClientFrame(second_stream, io, packet.items);
    switch (try targeted_eval.await(io)) {
        .value => |value| try std.testing.expectEqualStrings("7", value),
        .javascript_error => return error.UnexpectedJavaScriptError,
    }

    try second.close(io);
    const second_close = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(protocol.Command.close, second_close.header.command);
    try second_stream.shutdown(io, .both);
    try running.wait();
}
