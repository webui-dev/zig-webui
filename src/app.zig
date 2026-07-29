const std = @import("std");
const Linsang = @import("Linsang");
const browser = @import("browser.zig");
const protocol = @import("protocol.zig");

const bridge = @embedFile("bridge.js");
const default_max_pending_evals = 64;
const capability_len = 32;

pub const Tls = struct {
    certificate_pem: []const u8,
    private_key_pem: []const u8,
};

pub const Limits = struct {
    max_connections: usize = 128,
    max_unauthenticated_connections: usize = 16,
    max_ws_message_size: usize = 1 << 20,
    max_call_payload_size: usize = 64 << 10,
    max_argument_size: usize = 64 << 10,
    max_binding_name_size: usize = 256,
    max_event_size: usize = 8 << 10,
    max_script_size: usize = 256 << 10,

    fn validate(self: Limits) !void {
        const max_payload = self.max_ws_message_size -| protocol.header_len;
        if (self.max_connections == 0 or
            self.max_unauthenticated_connections == 0 or
            self.max_unauthenticated_connections > self.max_connections or
            self.max_ws_message_size <= protocol.header_len or
            self.max_call_payload_size == 0 or
            self.max_call_payload_size > max_payload or
            self.max_argument_size == 0 or
            self.max_argument_size > self.max_call_payload_size or
            self.max_binding_name_size == 0 or
            self.max_binding_name_size > self.max_call_payload_size or
            self.max_event_size == 0 or
            self.max_event_size > max_payload or
            self.max_script_size == 0 or
            self.max_script_size > max_payload)
        {
            return error.InvalidLimits;
        }
    }
};

pub const Handler = *const fn (*Call, ?*anyopaque) anyerror!void;
pub const EventHandler = *const fn (
    *const Event,
    ?*anyopaque,
) anyerror!void;
pub const Request = Linsang.Request;
pub const Response = Linsang.Response;

pub const EventKind = enum {
    connected,
    disconnected,
    click,
    navigation,
};

pub const Event = struct {
    kind: EventKind,
    client: Client,
    /// Element ID for clicks, URL for navigation, and empty for lifecycle
    /// events. The slice is only valid for the duration of the handler.
    data: []const u8 = "",
};

pub const ResourceHandler = *const fn (
    path: []const u8,
    request: *const Request,
    response: *Response,
    user_data: ?*anyopaque,
) anyerror!void;

pub const CustomResource = struct {
    handler: ResourceHandler,
    user_data: ?*anyopaque = null,
};

pub const Content = union(enum) {
    /// HTML copied into the window and served at its capability root.
    html: []const u8,
    /// Directory path opened by `App.start` and closed by `Running.stop`.
    directory: []const u8,
    /// Buffered resource handler. The bridge and WebSocket paths stay reserved.
    custom: CustomResource,
    /// HTTP(S) page opened directly. The page must load `Window.bridgeUrl`.
    external_url: []const u8,
};

const Binding = struct {
    name: []u8,
    handler: Handler,
    user_data: ?*anyopaque,
};

const EventBinding = struct {
    handler: EventHandler,
    user_data: ?*anyopaque,
};

pub const EvalResult = union(enum) {
    value: []const u8,
    javascript_error: []const u8,
};

pub const BroadcastEvalOutcome = union(enum) {
    value: []const u8,
    javascript_error: []const u8,
    failed: anyerror,
};

pub const BroadcastEval = struct {
    client: Client,
    outcome: BroadcastEvalOutcome,
};

pub const BroadcastEvalResults = struct {
    gpa: std.mem.Allocator,
    storage: []u8,
    items: []BroadcastEval,

    pub fn deinit(self: *BroadcastEvalResults) void {
        self.gpa.free(self.items);
        self.gpa.free(self.storage);
        self.* = undefined;
    }
};

fn isLoopbackAddress(address: std.Io.net.IpAddress) bool {
    return switch (address) {
        .ip4 => |ip4| ip4.bytes[0] == 127,
        .ip6 => |ip6| if (std.Io.net.Ip4Address.fromIp6(ip6)) |ip4|
            ip4.bytes[0] == 127
        else blk: {
            const loopback = std.Io.net.Ip6Address.loopback(0);
            break :blk std.mem.eql(
                u8,
                &ip6.bytes,
                &loopback.bytes,
            );
        },
    };
}

fn validateUrl(url: []const u8) !void {
    if (url.len == 0 or std.mem.indexOfScalar(u8, url, 0) != null)
        return error.InvalidUrl;
    if (!std.unicode.utf8ValidateSlice(url)) return error.InvalidUtf8;
}

fn validateExternalUrl(url: []const u8) !void {
    validateUrl(url) catch |err| return switch (err) {
        error.InvalidUtf8 => error.InvalidUtf8,
        else => error.InvalidExternalUrl,
    };
    const parsed = std.Uri.parse(url) catch return error.InvalidExternalUrl;
    if (parsed.host == null or
        !(std.ascii.eqlIgnoreCase(parsed.scheme, "http") or
            std.ascii.eqlIgnoreCase(parsed.scheme, "https")))
    {
        return error.InvalidExternalUrl;
    }
}

fn validateRunScript(script: []const u8, max_size: usize) !void {
    if (script.len == 0) return error.InvalidScript;
    if (script.len > max_size) return error.ScriptTooLarge;
    if (!std.unicode.utf8ValidateSlice(script)) return error.InvalidUtf8;
}

fn appendRawPayload(
    payload: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    function: []const u8,
    data: []const u8,
    max_size: usize,
) !void {
    if (function.len == 0 or std.mem.indexOfScalar(u8, function, 0) != null)
        return error.InvalidFunctionName;
    if (!std.unicode.utf8ValidateSlice(function)) return error.InvalidUtf8;
    const name_size = std.math.add(usize, function.len, 1) catch
        return error.MessageTooLarge;
    const size = std.math.add(usize, name_size, data.len) catch
        return error.MessageTooLarge;
    if (size > max_size) return error.MessageTooLarge;
    try payload.appendSlice(gpa, function);
    try payload.append(gpa, 0);
    try payload.appendSlice(gpa, data);
}

fn validateCallLimits(call: *const protocol.CallPayload, limits: Limits) !void {
    if (call.name.len > limits.max_binding_name_size)
        return error.BindingNameTooLarge;
    if (!std.unicode.utf8ValidateSlice(call.name)) return error.InvalidUtf8;
    for (call.slice()) |argument|
        if (argument.len > limits.max_argument_size)
            return error.ArgumentTooLarge;
}

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

const DirectoryContent = struct {
    path: []u8,
    dir: ?std.Io.Dir = null,
};

const StoredContent = union(enum) {
    html: []u8,
    directory: DirectoryContent,
    custom: CustomResource,
    external_url: []u8,

    fn init(gpa: std.mem.Allocator, content: Content) !StoredContent {
        return switch (content) {
            .html => |html| .{ .html = try gpa.dupe(u8, html) },
            .directory => |path| blk: {
                if (path.len == 0) return error.InvalidDirectory;
                break :blk .{ .directory = .{
                    .path = try gpa.dupe(u8, path),
                } };
            },
            .custom => |custom| .{ .custom = custom },
            .external_url => |url| blk: {
                try validateExternalUrl(url);
                break :blk .{ .external_url = try gpa.dupe(u8, url) };
            },
        };
    }

    fn deinit(self: *StoredContent, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .html => |html| gpa.free(html),
            .directory => |directory| {
                std.debug.assert(directory.dir == null);
                gpa.free(directory.path);
            },
            .custom => {},
            .external_url => |url| gpa.free(url),
        }
        self.* = undefined;
    }
};

const WindowState = struct {
    gpa: std.mem.Allocator,
    content: StoredContent,
    limits: Limits,
    max_clients: usize,
    max_pending_evals: usize,
    capability: [capability_len]u8 = @splat(0),
    token: u32 = 0,
    bindings: std.ArrayList(Binding) = .empty,
    event_binding: ?EventBinding = null,
    mutex: std.Io.Mutex = .init,
    clients: std.ArrayList(ConnectedClient) = .empty,
    pending_evals: std.ArrayList(*PendingEval) = .empty,
    next_client_id: u64 = 1,
    next_eval_id: u16 = 1,

    fn deinit(self: *WindowState) void {
        std.debug.assert(self.pending_evals.items.len == 0);
        self.pending_evals.deinit(self.gpa);
        for (self.clients.items) |*connected| connected.peer.deinit();
        self.clients.deinit(self.gpa);
        for (self.bindings.items) |item| self.gpa.free(item.name);
        self.bindings.deinit(self.gpa);
        self.content.deinit(self.gpa);
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

    fn hasConnection(
        self: *WindowState,
        connection: *Linsang.Connection,
    ) bool {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        return self.clientIndexByKey(@intFromPtr(connection)) != null;
    }

    fn hasClients(self: *WindowState, io: std.Io) bool {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.clients.items.len != 0;
    }

    fn authenticate(
        self: *WindowState,
        connection: *Linsang.Connection,
    ) !?Client {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const key = @intFromPtr(connection);
        if (self.clientIndexByKey(key) != null) return null;
        if (self.clients.items.len >= self.max_clients)
            return error.ClientLimitReached;

        var peer = try connection.peer();
        errdefer peer.deinit();
        const client_id = self.next_client_id;
        try self.clients.append(self.gpa, .{
            .id = client_id,
            .key = key,
            .peer = peer,
        });
        self.next_client_id +%= 1;
        if (self.next_client_id == 0) self.next_client_id = 1;
        return .{ .state = self, .client_id = client_id };
    }

    fn client(self: *WindowState, connection: *Linsang.Connection) ?Client {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const index = self.clientIndexByKey(@intFromPtr(connection)) orelse
            return null;
        return .{ .state = self, .client_id = self.clients.items[index].id };
    }

    fn disconnected(
        self: *WindowState,
        connection: *Linsang.Connection,
    ) ?Client {
        self.mutex.lockUncancelable(connection.io);
        defer self.mutex.unlock(connection.io);
        const index = self.clientIndexByKey(@intFromPtr(connection)) orelse
            return null;
        var disconnected_client = self.clients.swapRemove(index);
        disconnected_client.peer.deinit();
        for (self.pending_evals.items) |pending| {
            if (pending.client_id == disconnected_client.id) {
                pending.status = .disconnected;
                pending.done.set(connection.io);
            }
        }
        return .{
            .state = self,
            .client_id = disconnected_client.id,
        };
    }

    fn dispatch(self: *WindowState, event: Event) void {
        const registered = self.event_binding orelse return;
        registered.handler(&event, registered.user_data) catch |err|
            std.log.err("WebUI event handler failed: {}", .{err});
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
        const pending = for (self.pending_evals.items) |candidate| {
            if (candidate.id == id and candidate.client_id == client_id)
                break candidate;
        } else return;
        if (pending.status != .waiting) return;

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

    fn pendingIndex(self: *WindowState, pending: *PendingEval) ?usize {
        for (self.pending_evals.items, 0..) |candidate, index|
            if (candidate == pending) return index;
        return null;
    }

    fn removeEval(self: *WindowState, io: std.Io, pending: *PendingEval) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const index = self.pendingIndex(pending) orelse return;
        _ = self.pending_evals.swapRemove(index);
    }

    fn takeEval(
        self: *WindowState,
        io: std.Io,
        pending: *PendingEval,
    ) !EvalResult {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const index = self.pendingIndex(pending) orelse
            return error.ConnectionClosed;
        _ = self.pending_evals.swapRemove(index);
        const value = pending.buffer[0..pending.len];
        return switch (pending.status) {
            .value => .{ .value = value },
            .javascript_error => .{ .javascript_error = value },
            .result_too_large => error.ResultTooLarge,
            .disconnected => error.ConnectionClosed,
            .waiting => error.Timeout,
        };
    }

    fn nextEvalId(self: *WindowState) u16 {
        while (true) {
            const id = self.next_eval_id;
            self.next_eval_id +%= 1;
            if (self.next_eval_id == 0) self.next_eval_id = 1;
            for (self.pending_evals.items) |pending| {
                if (pending.id == id) break;
            } else return id;
        }
    }

    fn snapshotClients(
        self: *WindowState,
        io: std.Io,
    ) ![]Client {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const clients = try self.gpa.alloc(Client, self.clients.items.len);
        for (self.clients.items, clients) |connected, *snapshot|
            snapshot.* = .{ .state = self, .client_id = connected.id };
        return clients;
    }

    fn broadcast(
        self: *WindowState,
        io: std.Io,
        command: protocol.Command,
        payload: []const u8,
    ) !usize {
        if (payload.len > self.limits.max_ws_message_size - protocol.header_len)
            return error.MessageTooLarge;
        self.mutex.lockUncancelable(io);
        const peers = self.gpa.alloc(
            Linsang.WebSocketPeer,
            self.clients.items.len,
        ) catch |err| {
            self.mutex.unlock(io);
            return err;
        };
        for (self.clients.items, peers) |connected, *peer|
            peer.* = connected.peer.clone();
        self.mutex.unlock(io);
        defer {
            for (peers) |*peer| peer.deinit();
            self.gpa.free(peers);
        }

        var packet: std.ArrayList(u8) = .empty;
        defer packet.deinit(self.gpa);
        try protocol.append(&packet, self.gpa, .{
            .token = self.token,
            .command = command,
        }, payload);

        var sent: usize = 0;
        for (peers) |peer| {
            peer.sendBinary(packet.items) catch |err| switch (err) {
                error.Closed => continue,
                else => return err,
            };
            sent += 1;
        }
        return sent;
    }

    fn eval(
        self: *WindowState,
        io: std.Io,
        target_client_id: ?u64,
        script: []const u8,
        result_buffer: []u8,
        timeout: std.Io.Duration,
    ) !EvalResult {
        try validateRunScript(script, self.limits.max_script_size);

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

        var pending: PendingEval = undefined;
        self.mutex.lockUncancelable(io);
        if (self.pending_evals.items.len >= self.max_pending_evals) {
            self.mutex.unlock(io);
            return error.TooManyPendingEvals;
        }
        pending = .{
            .id = self.nextEvalId(),
            .client_id = client_id,
            .buffer = result_buffer,
        };
        self.pending_evals.append(self.gpa, &pending) catch |err| {
            self.mutex.unlock(io);
            return err;
        };
        self.mutex.unlock(io);
        errdefer self.removeEval(io, &pending);

        var packet: std.ArrayList(u8) = .empty;
        defer packet.deinit(self.gpa);
        try protocol.append(&packet, self.gpa, .{
            .token = self.token,
            .id = pending.id,
            .command = .js,
        }, script);
        peer.sendBinary(packet.items) catch |err| switch (err) {
            error.Closed => return error.ConnectionClosed,
            else => return err,
        };

        while (true) {
            pending.done.waitTimeout(io, .{ .deadline = deadline }) catch |wait_error| {
                self.mutex.lockUncancelable(io);
                const still_waiting = pending.status == .waiting;
                self.mutex.unlock(io);
                if (!still_waiting) break;
                if (wait_error == error.Canceled) return wait_error;
                if (deadline.compare(.lte, .now(io, .awake)))
                    return error.Timeout;
                continue;
            };
            break;
        }
        return self.takeEval(io, &pending);
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
        if (value.len > self.client.state.limits.max_ws_message_size - protocol.header_len)
            return error.ResponseTooLarge;
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
        if (payload.len > self.state.limits.max_ws_message_size - protocol.header_len)
            return error.MessageTooLarge;
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

    /// Execute JavaScript without waiting for a result or browser error.
    pub fn run(self: Client, io: std.Io, script: []const u8) !void {
        try validateRunScript(script, self.state.limits.max_script_size);
        try self.send(io, .js_quick, script);
    }

    pub fn navigate(self: Client, io: std.Io, url: []const u8) !void {
        try validateUrl(url);
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
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.state.gpa);
        try appendRawPayload(
            &payload,
            self.state.gpa,
            function,
            data,
            self.state.limits.max_ws_message_size - protocol.header_len,
        );
        try self.send(io, .raw, payload.items);
    }
};

fn evalBroadcastClient(
    client: Client,
    io: std.Io,
    script: []const u8,
    result_buffer: []u8,
    timeout: std.Io.Duration,
    output: *BroadcastEval,
) std.Io.Cancelable!void {
    const result = client.eval(io, script, result_buffer, timeout) catch |err| {
        output.* = .{ .client = client, .outcome = .{ .failed = err } };
        if (err == error.Canceled) return error.Canceled;
        return;
    };
    output.* = .{
        .client = client,
        .outcome = switch (result) {
            .value => |value| .{ .value = value },
            .javascript_error => |message| .{ .javascript_error = message },
        },
    };
}

pub const Window = struct {
    state: *WindowState,

    /// Install the browser event handler before starting the application.
    pub fn onEvent(
        self: Window,
        handler: EventHandler,
        user_data: ?*anyopaque,
    ) void {
        self.state.event_binding = .{
            .handler = handler,
            .user_data = user_data,
        };
    }

    pub fn bind(
        self: Window,
        name: []const u8,
        handler: Handler,
        user_data: ?*anyopaque,
    ) !void {
        if (name.len == 0 or std.mem.indexOfScalar(u8, name, 0) != null)
            return error.InvalidBindingName;
        if (name.len > self.state.limits.max_binding_name_size)
            return error.BindingNameTooLarge;
        if (!std.unicode.utf8ValidateSlice(name)) return error.InvalidUtf8;
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
        const page_url = try self.url(running, self.state.gpa);
        defer self.state.gpa.free(page_url);
        try browser.open(self.state.gpa, io, page_url);
    }

    pub fn url(
        self: Window,
        running: *const Running,
        gpa: std.mem.Allocator,
    ) ![]u8 {
        if (running.stopped) return error.NotRunning;
        if (!running.app.hasWindow(self.state)) return error.UnknownWindow;
        switch (self.state.content) {
            .external_url => |external| return gpa.dupe(u8, external),
            else => {},
        }
        const scheme = if (running.app.options.tls == null) "http" else "https";
        return if (std.mem.indexOfScalar(
            u8,
            running.app.options.address,
            ':',
        ) == null)
            std.fmt.allocPrint(gpa, "{s}://{s}:{d}/{s}/", .{
                scheme,
                running.app.options.address,
                running.inner.address.getPort(),
                self.state.capability,
            })
        else
            std.fmt.allocPrint(gpa, "{s}://[{s}]:{d}/{s}/", .{
                scheme,
                running.app.options.address,
                running.inner.address.getPort(),
                self.state.capability,
            });
    }

    /// Return the capability-scoped bridge URL for this window.
    pub fn bridgeUrl(
        self: Window,
        running: *const Running,
        gpa: std.mem.Allocator,
    ) ![]u8 {
        if (running.stopped) return error.NotRunning;
        if (!running.app.hasWindow(self.state)) return error.UnknownWindow;
        const scheme = if (running.app.options.tls == null) "http" else "https";
        return if (std.mem.indexOfScalar(
            u8,
            running.app.options.address,
            ':',
        ) == null)
            std.fmt.allocPrint(gpa, "{s}://{s}:{d}/{s}/webui.js", .{
                scheme,
                running.app.options.address,
                running.inner.address.getPort(),
                self.state.capability,
            })
        else
            std.fmt.allocPrint(gpa, "{s}://[{s}]:{d}/{s}/webui.js", .{
                scheme,
                running.app.options.address,
                running.inner.address.getPort(),
                self.state.capability,
            });
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

    pub fn evalAll(
        self: Window,
        io: std.Io,
        script: []const u8,
        result_buffer_size: usize,
        timeout: std.Io.Duration,
    ) !BroadcastEvalResults {
        try validateRunScript(script, self.state.limits.max_script_size);

        const clients = try self.state.snapshotClients(io);
        defer self.state.gpa.free(clients);
        const storage_len = std.math.mul(
            usize,
            clients.len,
            result_buffer_size,
        ) catch return error.ResultBufferTooLarge;
        const storage = try self.state.gpa.alloc(u8, storage_len);
        errdefer self.state.gpa.free(storage);
        const items = try self.state.gpa.alloc(BroadcastEval, clients.len);
        errdefer self.state.gpa.free(items);

        var group: std.Io.Group = .init;
        defer group.cancel(io);
        for (clients, items, 0..) |client, *item, index| {
            const start = index * result_buffer_size;
            group.async(io, evalBroadcastClient, .{
                client,
                io,
                script,
                storage[start..][0..result_buffer_size],
                timeout,
                item,
            });
        }
        try group.await(io);
        return .{ .gpa = self.state.gpa, .storage = storage, .items = items };
    }

    /// Execute JavaScript on all clients without waiting for results.
    pub fn run(self: Window, io: std.Io, script: []const u8) !usize {
        try validateRunScript(script, self.state.limits.max_script_size);
        return self.state.broadcast(io, .js_quick, script);
    }

    pub fn navigate(self: Window, io: std.Io, target_url: []const u8) !usize {
        try validateUrl(target_url);
        return self.state.broadcast(io, .navigation, target_url);
    }

    pub fn close(self: Window, io: std.Io) !usize {
        return self.state.broadcast(io, .close, "");
    }

    pub fn sendRaw(
        self: Window,
        io: std.Io,
        function: []const u8,
        data: []const u8,
    ) !usize {
        var payload: std.ArrayList(u8) = .empty;
        defer payload.deinit(self.state.gpa);
        try appendRawPayload(
            &payload,
            self.state.gpa,
            function,
            data,
            self.state.limits.max_ws_message_size - protocol.header_len,
        );
        return self.state.broadcast(io, .raw, payload.items);
    }
};

pub const App = struct {
    gpa: std.mem.Allocator,
    options: Options,
    windows: std.ArrayList(*WindowState) = .empty,
    server: ?Linsang.Server = null,
    tls_auth: ?Linsang.tls.CertKeyPair = null,
    started: bool = false,
    closed: std.atomic.Value(bool) = .init(false),
    unauthenticated_connections: std.atomic.Value(usize) = .init(0),

    pub const Options = struct {
        address: []const u8 = "127.0.0.1",
        port: u16 = 0,
        public: bool = false,
        tls: ?Tls = null,
        limits: Limits = .{},
    };

    pub const WindowOptions = struct {
        content: Content,
        /// One client by default; values above one explicitly enable
        /// bounded multi-client mode.
        max_clients: usize = 1,
        /// Maximum number of concurrent Zig-to-JavaScript calls.
        max_pending_evals: usize = default_max_pending_evals,
    };

    pub fn init(gpa: std.mem.Allocator, options: Options) App {
        return .{ .gpa = gpa, .options = options };
    }

    pub fn deinit(self: *App) void {
        std.debug.assert(!self.started);
        std.debug.assert(self.tls_auth == null);
        for (self.windows.items) |window| window.deinit();
        self.windows.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn createWindow(self: *App, options: WindowOptions) !Window {
        if (self.started) return error.AlreadyStarted;
        try self.options.limits.validate();
        if (options.max_clients == 0) return error.InvalidClientLimit;
        if (options.max_pending_evals == 0 or
            options.max_pending_evals > std.math.maxInt(u16))
        {
            return error.InvalidPendingEvalLimit;
        }
        const state = try self.gpa.create(WindowState);
        errdefer self.gpa.destroy(state);
        var content = try StoredContent.init(self.gpa, options.content);
        errdefer content.deinit(self.gpa);
        state.* = .{
            .gpa = self.gpa,
            .content = content,
            .limits = self.options.limits,
            .max_clients = options.max_clients,
            .max_pending_evals = options.max_pending_evals,
        };
        try self.windows.append(self.gpa, state);
        return .{ .state = state };
    }

    pub fn start(self: *App, io: std.Io) !Running {
        if (self.started) return error.AlreadyStarted;
        if (self.windows.items.len == 0) return error.NoWindow;
        try self.validateNetworkOptions();
        for (self.windows.items) |window| {
            window.limits = self.options.limits;
            for (window.bindings.items) |binding|
                if (binding.name.len > window.limits.max_binding_name_size)
                    return error.BindingNameTooLarge;
        }
        errdefer self.closeDirectories(io);
        try self.openDirectories(io);
        if (self.options.tls) |tls| {
            self.tls_auth = try Linsang.tls.CertKeyPair.fromSlice(
                self.gpa,
                io,
                tls.certificate_pem,
                tls.private_key_pem,
            );
        }
        errdefer self.deinitTls();
        for (self.windows.items, 0..) |window, index| {
            while (true) {
                var random: [20]u8 = undefined;
                try io.randomSecure(&random);
                window.token = std.mem.readInt(u32, random[0..4], .little);
                if (window.token == 0) continue;
                window.capability = std.fmt.bytesToHex(random[4..], .lower);
                for (self.windows.items[0..index]) |existing| {
                    if (std.mem.eql(
                        u8,
                        &window.capability,
                        &existing.capability,
                    )) break;
                } else break;
            }
        }
        self.closed.store(false, .release);
        self.unauthenticated_connections.store(0, .release);
        self.server = Linsang.Server.init(self.gpa, .{
            .address = self.options.address,
            .port = self.options.port,
            .max_connections = self.options.limits.max_connections,
            .max_ws_message_size = self.options.limits.max_ws_message_size,
            .ws_idle_timeout = null,
            .tls = if (self.tls_auth) |*auth| .{ .auth = auth } else null,
            .on_request = onRequest,
            .on_ws_open = onOpen,
            .on_ws_message = onMessage,
            .on_ws_close = onClose,
            .user_data = self,
        });
        errdefer self.server = null;
        const inner = try self.server.?.start(io);
        self.started = true;
        return .{ .app = self, .inner = inner };
    }

    fn validateNetworkOptions(self: *const App) !void {
        try self.options.limits.validate();
        const address = std.Io.net.IpAddress.parse(
            self.options.address,
            self.options.port,
        ) catch return error.InvalidAddress;
        if (!isLoopbackAddress(address)) {
            if (!self.options.public) return error.PublicListeningNotEnabled;
            if (self.options.tls == null) return error.TlsRequired;
        }
        if (self.options.tls) |tls| {
            if (tls.certificate_pem.len == 0 or tls.private_key_pem.len == 0)
                return error.InvalidTlsConfiguration;
        }
    }

    fn deinitTls(self: *App) void {
        if (self.tls_auth) |*auth| auth.deinit(self.gpa);
        self.tls_auth = null;
    }

    fn openDirectories(self: *App, io: std.Io) !void {
        for (self.windows.items) |window| switch (window.content) {
            .directory => |*directory| {
                std.debug.assert(directory.dir == null);
                directory.dir = if (std.fs.path.isAbsolute(directory.path))
                    try std.Io.Dir.openDirAbsolute(io, directory.path, .{
                        .follow_symlinks = false,
                    })
                else
                    try std.Io.Dir.cwd().openDir(io, directory.path, .{
                        .follow_symlinks = false,
                    });
            },
            else => {},
        };
    }

    fn closeDirectories(self: *App, io: std.Io) void {
        for (self.windows.items) |window| switch (window.content) {
            .directory => |*directory| if (directory.dir) |dir| {
                dir.close(io);
                directory.dir = null;
            },
            else => {},
        };
    }

    fn hasWindow(self: *const App, state: *WindowState) bool {
        // ponytail: window counts are tiny; use a map if hundreds become normal.
        for (self.windows.items) |window|
            if (window == state) return true;
        return false;
    }

    fn windowByCapability(
        self: *const App,
        capability: []const u8,
    ) ?*WindowState {
        for (self.windows.items) |window|
            if (std.mem.eql(u8, &window.capability, capability)) return window;
        return null;
    }

    fn windowForConnection(
        self: *const App,
        connection: *Linsang.Connection,
    ) ?*WindowState {
        for (self.windows.items) |window|
            if (window.hasConnection(connection)) return window;
        return null;
    }

    fn hasClients(self: *const App, io: std.Io) bool {
        for (self.windows.items) |window|
            if (window.hasClients(io)) return true;
        return false;
    }
};

pub const Running = struct {
    app: *App,
    inner: Linsang.server.Running,
    stopped: bool = false,

    pub fn stop(self: *Running) !void {
        if (self.stopped) return;
        try self.inner.stop();
        self.app.closeDirectories(self.inner.io);
        self.app.deinitTls();
        self.stopped = true;
        self.app.started = false;
        self.app.server = null;
        std.debug.assert(
            self.app.unauthenticated_connections.load(.acquire) == 0,
        );
    }

    pub fn wait(self: *Running) !void {
        // ponytail: polling is enough for UI shutdown; use an event if latency
        // below 10 ms becomes meaningful.
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

const Route = struct {
    window: *WindowState,
    resource: []const u8,
};

fn effectivePort(uri: std.Uri) ?u16 {
    if (uri.port) |port| return port;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "http")) return 80;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) return 443;
    return null;
}

fn sameOrigin(origin_text: []const u8, target_text: []const u8) bool {
    const origin = std.Uri.parse(origin_text) catch return false;
    const target = std.Uri.parse(target_text) catch return false;
    if (origin.user != null or
        origin.password != null or
        !origin.path.isEmpty() or
        origin.query != null or
        origin.fragment != null or
        !std.ascii.eqlIgnoreCase(origin.scheme, target.scheme) or
        effectivePort(origin) != effectivePort(target))
    {
        return false;
    }

    var origin_host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    var target_host_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const origin_host = origin.getHost(&origin_host_buffer) catch return false;
    const target_host = target.getHost(&target_host_buffer) catch return false;
    return std.ascii.eqlIgnoreCase(origin_host.bytes, target_host.bytes);
}

fn originAllowed(
    app: *const App,
    window: *const WindowState,
    request: *const Linsang.Request,
) bool {
    const origin = request.header("origin") orelse return false;
    return switch (window.content) {
        .external_url => |external| sameOrigin(origin, external),
        else => blk: {
            const host = request.header("host") orelse break :blk false;
            var target_buffer: [std.Io.net.HostName.max_len + 32]u8 = undefined;
            const target = std.fmt.bufPrint(
                &target_buffer,
                "{s}://{s}",
                .{ if (app.options.tls == null) "http" else "https", host },
            ) catch break :blk false;
            break :blk sameOrigin(origin, target);
        },
    };
}

fn route(app: *const App, path: []const u8) ?Route {
    if (path.len < capability_len + 2 or
        path[0] != '/' or
        path[capability_len + 1] != '/')
    {
        return null;
    }
    return .{
        .window = app.windowByCapability(path[1 .. capability_len + 1]) orelse
            return null,
        .resource = path[capability_len + 2 ..],
    };
}

fn onRequest(
    request: *const Linsang.Request,
    response: *Linsang.Response,
    user_data: ?*anyopaque,
) Linsang.Action {
    const app = appFrom(user_data);
    const resolved = route(app, request.path) orelse {
        response.status = .not_found;
        return .respond;
    };
    const window = resolved.window;
    if (std.mem.eql(u8, resolved.resource, "_webui_ws_connect")) {
        if (!originAllowed(app, window, request)) {
            response.status = .forbidden;
            return .respond;
        }
        return .upgrade;
    }
    if (std.mem.eql(u8, resolved.resource, "webui.js")) {
        response.setHeader("Content-Type", "text/javascript; charset=utf-8") catch
            return failResponse(response);
        response.print("globalThis.__zigWebuiToken={d};\n", .{window.token}) catch
            return failResponse(response);
        response.print(
            "globalThis.__zigWebuiCapability=\"{s}\";\n",
            .{window.capability},
        ) catch return failResponse(response);
        response.print(
            "globalThis.__zigWebuiEvents={};\n",
            .{window.event_binding != null},
        ) catch return failResponse(response);
        response.write(bridge) catch return failResponse(response);
        return .respond;
    }
    return switch (window.content) {
        .html => |html| if (resolved.resource.len == 0) blk: {
            response.setHeader("Content-Type", "text/html; charset=utf-8") catch
                break :blk failResponse(response);
            response.write(html) catch break :blk failResponse(response);
            break :blk .respond;
        } else blk: {
            response.status = .not_found;
            break :blk .respond;
        },
        .directory => |directory| blk: {
            const dir = directory.dir orelse break :blk failResponse(response);
            // ponytail: Linsang StaticFiles has no mount prefix yet. Rewrite
            // only the validated path slice; use strip_prefix when available.
            @constCast(request).path = request.path[capability_len + 1 ..];
            break :blk .{ .files = .{ .dir = dir } };
        },
        .custom => |custom| blk: {
            custom.handler(
                resolved.resource,
                request,
                response,
                custom.user_data,
            ) catch break :blk failResponse(response);
            break :blk .respond;
        },
        .external_url => blk: {
            response.status = .not_found;
            break :blk .respond;
        },
    };
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

fn onOpen(connection: *Linsang.Connection, user_data: ?*anyopaque) void {
    const app = appFrom(user_data);
    const previous = app.unauthenticated_connections.fetchAdd(1, .acq_rel);
    if (previous >= app.options.limits.max_unauthenticated_connections)
        connection.wsClose(.policy_violation, "");
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
    const packet = protocol.decode(message.data) catch {
        connection.wsClose(.protocol_error, "");
        return;
    };

    // ponytail: Linsang does not retain the upgrade route; bind the connection
    // with the capability in its first authenticated protocol packet.
    const authenticated = app.windowForConnection(connection);
    if (packet.header.command == .check_token) {
        const window = app.windowByCapability(packet.payload) orelse {
            send(connection, app.gpa, packet.header, &.{0}) catch {};
            return;
        };
        if (packet.header.token != window.token or
            (authenticated != null and authenticated.? != window))
        {
            send(connection, app.gpa, packet.header, &.{0}) catch {};
            return;
        }
        const new_client = window.authenticate(connection) catch {
            send(connection, app.gpa, packet.header, &.{0}) catch {};
            connection.wsClose(.policy_violation, "");
            return;
        };
        send(connection, app.gpa, packet.header, &.{1}) catch {};
        if (new_client) |client| {
            const previous = app.unauthenticated_connections.fetchSub(
                1,
                .acq_rel,
            );
            std.debug.assert(previous > 0);
            window.dispatch(.{
                .kind = .connected,
                .client = client,
            });
        }
        return;
    }
    const window = authenticated orelse {
        connection.wsClose(.policy_violation, "");
        return;
    };
    if (packet.header.token != window.token) {
        connection.wsClose(.policy_violation, "");
        return;
    }

    switch (packet.header.command) {
        .js => window.finishEval(
            connection,
            packet.header.id,
            packet.payload,
        ) catch connection.wsClose(.protocol_error, ""),
        .call => {
            if (packet.payload.len > window.limits.max_call_payload_size) {
                connection.wsClose(.message_too_big, "");
                return;
            }
            const client = window.client(connection) orelse {
                connection.wsClose(.policy_violation, "");
                return;
            };
            const decoded = protocol.decodeCall(packet.payload) catch {
                connection.wsClose(.protocol_error, "");
                return;
            };
            validateCallLimits(&decoded, window.limits) catch |err| {
                connection.wsClose(
                    if (err == error.InvalidUtf8)
                        .protocol_error
                    else
                        .message_too_big,
                    "",
                );
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
        .click, .navigation => {
            if (packet.payload.len > window.limits.max_event_size) {
                connection.wsClose(.message_too_big, "");
                return;
            }
            const client = window.client(connection) orelse {
                connection.wsClose(.policy_violation, "");
                return;
            };
            const data = protocol.decodeEventText(packet.payload) catch {
                connection.wsClose(.protocol_error, "");
                return;
            };
            window.dispatch(.{
                .kind = if (packet.header.command == .click)
                    .click
                else
                    .navigation,
                .client = client,
                .data = data,
            });
        },
        else => connection.wsClose(.unsupported_data, ""),
    }
}

fn onClose(connection: *Linsang.Connection, user_data: ?*anyopaque) void {
    const app = appFrom(user_data);
    var authenticated = false;
    for (app.windows.items) |window| {
        if (window.disconnected(connection)) |client| {
            window.dispatch(.{
                .kind = .disconnected,
                .client = client,
            });
            authenticated = true;
        }
    }
    if (!authenticated) {
        const previous = app.unauthenticated_connections.fetchSub(1, .acq_rel);
        std.debug.assert(previous > 0);
    }
    if (authenticated and !app.hasClients(connection.io))
        app.closed.store(true, .release);
}

test "network options, origins, and protocol limits" {
    const gpa = std.testing.allocator;
    try (Limits{}).validate();
    try std.testing.expectError(
        error.InvalidLimits,
        (Limits{ .max_ws_message_size = protocol.header_len }).validate(),
    );
    try std.testing.expect(isLoopbackAddress(
        try std.Io.net.IpAddress.parse("127.42.0.1", 0),
    ));
    try std.testing.expect(isLoopbackAddress(
        try std.Io.net.IpAddress.parse("::1", 0),
    ));
    try std.testing.expect(!isLoopbackAddress(
        try std.Io.net.IpAddress.parse("0.0.0.0", 0),
    ));
    try std.testing.expect(sameOrigin(
        "https://EXAMPLE.com",
        "https://example.com:443/app",
    ));
    try std.testing.expect(!sameOrigin(
        "https://example.com/path",
        "https://example.com",
    ));
    try std.testing.expect(!sameOrigin(
        "https://example.com",
        "https://example.com:444",
    ));
    const oversized_call = try protocol.decodeCall("x\x004\x001234\x00");
    try std.testing.expectError(
        error.ArgumentTooLarge,
        validateCallLimits(
            &oversized_call,
            .{ .max_argument_size = 3 },
        ),
    );
    const invalid_name = try protocol.decodeCall("\xff\x00\x00");
    try std.testing.expectError(
        error.InvalidUtf8,
        validateCallLimits(&invalid_name, .{}),
    );

    var private_app = App.init(gpa, .{ .address = "0.0.0.0" });
    defer private_app.deinit();
    try std.testing.expectError(
        error.PublicListeningNotEnabled,
        private_app.validateNetworkOptions(),
    );

    var insecure_public_app = App.init(gpa, .{
        .address = "0.0.0.0",
        .public = true,
    });
    defer insecure_public_app.deinit();
    try std.testing.expectError(
        error.TlsRequired,
        insecure_public_app.validateNetworkOptions(),
    );

    var public_app = App.init(gpa, .{
        .address = "0.0.0.0",
        .public = true,
        .tls = .{
            .certificate_pem = "certificate",
            .private_key_pem = "key",
        },
        .limits = .{ .max_binding_name_size = 3 },
    });
    defer public_app.deinit();
    try public_app.validateNetworkOptions();
    const window = try public_app.createWindow(.{
        .content = .{ .html = "limits" },
    });
    try std.testing.expectError(
        error.BindingNameTooLarge,
        window.bind("long", integrationHandler, null),
    );
    try std.testing.expectError(error.ScriptTooLarge, validateRunScript("1234", 3));

    var invalid_tls_app = App.init(gpa, .{
        .tls = .{
            .certificate_pem = "certificate",
            .private_key_pem = "key",
        },
    });
    defer invalid_tls_app.deinit();
    _ = try invalid_tls_app.createWindow(.{
        .content = .{ .html = "tls" },
    });
    try std.testing.expectError(
        error.MissingEndMarker,
        invalid_tls_app.start(std.testing.io),
    );
}

test "call accessors, window creation, and routes" {
    const gpa = std.testing.allocator;
    var invalid_app = App.init(gpa, .{});
    defer invalid_app.deinit();
    try std.testing.expectError(
        error.InvalidClientLimit,
        invalid_app.createWindow(.{
            .content = .{ .html = "invalid" },
            .max_clients = 0,
        }),
    );
    var invalid_pending_app = App.init(gpa, .{});
    defer invalid_pending_app.deinit();
    try std.testing.expectError(
        error.InvalidPendingEvalLimit,
        invalid_pending_app.createWindow(.{
            .content = .{ .html = "invalid" },
            .max_pending_evals = 0,
        }),
    );

    var app = App.init(gpa, .{});
    defer app.deinit();
    try std.testing.expectError(error.InvalidDirectory, app.createWindow(.{
        .content = .{ .directory = "" },
    }));
    try std.testing.expectError(error.InvalidExternalUrl, app.createWindow(.{
        .content = .{ .external_url = "file:///tmp/index.html" },
    }));
    const window = try app.createWindow(.{
        .content = .{ .html = "hello" },
    });
    const second = try app.createWindow(.{
        .content = .{ .html = "again" },
    });
    try std.testing.expect(window.state != second.state);
    @memcpy(
        &window.state.capability,
        "0123456789abcdef0123456789abcdef",
    );
    const resolved = route(
        &app,
        "/0123456789abcdef0123456789abcdef/webui.js",
    ).?;
    try std.testing.expect(resolved.window == window.state);
    try std.testing.expectEqualStrings("webui.js", resolved.resource);
    try std.testing.expect(route(&app, "/short/") == null);
    try std.testing.expect(route(
        &app,
        "/ffffffffffffffffffffffffffffffff/",
    ) == null);

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

const IntegrationEventState = struct {
    expected_click: []const u8,
    connected: std.atomic.Value(bool) = .init(false),
    disconnected: std.atomic.Value(bool) = .init(false),
    clicked: std.atomic.Value(bool) = .init(false),
    navigated: std.atomic.Value(bool) = .init(false),
};

fn integrationEventHandler(
    event: *const Event,
    user_data: ?*anyopaque,
) !void {
    const state: *IntegrationEventState =
        @ptrCast(@alignCast(user_data.?));
    switch (event.kind) {
        .connected => state.connected.store(true, .release),
        .disconnected => state.disconnected.store(true, .release),
        .click => {
            if (!std.mem.eql(u8, event.data, state.expected_click))
                return error.UnexpectedClick;
            state.clicked.store(true, .release);
        },
        .navigation => {
            if (!std.mem.eql(u8, event.data, "http://localhost/next"))
                return error.UnexpectedNavigation;
            state.navigated.store(true, .release);
        },
    }
}

fn integrationResourceHandler(
    path: []const u8,
    request: *const Request,
    response: *Response,
    _: ?*anyopaque,
) !void {
    try response.setHeader("Content-Type", "text/plain; charset=utf-8");
    try response.print("{s}?{s}", .{ path, request.query });
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

fn getTestPath(
    address: std.Io.net.IpAddress,
    io: std.Io,
    target: []const u8,
    terminator: []const u8,
    response: []u8,
) ![]u8 {
    const client = try address.connect(io, .{ .mode = .stream });
    defer client.close(io);
    var request: [512]u8 = undefined;
    try writeAll(
        client,
        io,
        try std.fmt.bufPrint(
            &request,
            "GET {s} HTTP/1.1\r\nHost: localhost\r\n" ++
                "Connection: close\r\n\r\n",
            .{target},
        ),
    );
    return readUntil(client, io, response, terminator);
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

fn connectTestWebSocketOrigin(
    address: std.Io.net.IpAddress,
    io: std.Io,
    capability: []const u8,
    origin: []const u8,
) !std.Io.net.Stream {
    const stream = try address.connect(io, .{ .mode = .stream });
    errdefer stream.close(io);
    var request: [512]u8 = undefined;
    try writeAll(
        stream,
        io,
        try std.fmt.bufPrint(
            &request,
            "GET /{s}/_webui_ws_connect HTTP/1.1\r\n" ++
                "Host: localhost\r\nUpgrade: websocket\r\n" ++
                "Connection: Upgrade\r\n" ++
                "Origin: {s}\r\n" ++
                "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n" ++
                "Sec-WebSocket-Version: 13\r\n\r\n",
            .{ capability, origin },
        ),
    );
    var handshake: [512]u8 = undefined;
    const accepted = try readUntil(stream, io, &handshake, "\r\n\r\n");
    if (!std.mem.startsWith(u8, accepted, "HTTP/1.1 101"))
        return error.WebSocketUpgradeFailed;
    return stream;
}

fn connectTestWebSocket(
    address: std.Io.net.IpAddress,
    io: std.Io,
    capability: []const u8,
) !std.Io.net.Stream {
    return connectTestWebSocketOrigin(
        address,
        io,
        capability,
        "http://localhost",
    );
}

fn authenticateTestClient(
    stream: std.Io.net.Stream,
    io: std.Io,
    gpa: std.mem.Allocator,
    token: u32,
    capability: []const u8,
    response_buffer: []u8,
) !bool {
    var packet: std.ArrayList(u8) = .empty;
    defer packet.deinit(gpa);
    try protocol.append(&packet, gpa, .{
        .token = token,
        .command = .check_token,
    }, capability);
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

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "public");
    try tmp.dir.writeFile(io, .{
        .sub_path = "public/index.html",
        .data = "<h1>directory page</h1>",
    });
    try tmp.dir.writeFile(io, .{
        .sub_path = "secret.txt",
        .data = "not public",
    });
    const directory_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/public",
        .{tmp.sub_path},
    );
    defer gpa.free(directory_path);

    var app = App.init(gpa, .{});
    defer app.deinit();
    const window = try app.createWindow(.{
        .content = .{ .html = "test page" },
    });
    const second_window = try app.createWindow(.{
        .content = .{ .html = "second page" },
    });
    const directory_window = try app.createWindow(.{
        .content = .{ .directory = directory_path },
    });
    const custom_window = try app.createWindow(.{
        .content = .{ .custom = .{
            .handler = integrationResourceHandler,
        } },
    });
    const external_url = "http://external.example/app";
    const external_window = try app.createWindow(.{
        .content = .{ .external_url = external_url },
    });
    var primary_events: IntegrationEventState = .{
        .expected_click = "primary",
    };
    window.onEvent(integrationEventHandler, &primary_events);
    var secondary_events: IntegrationEventState = .{
        .expected_click = "secondary",
    };
    second_window.onEvent(integrationEventHandler, &secondary_events);
    var called_client_id: std.atomic.Value(u64) = .init(0);
    try window.bind("greet", integrationHandler, &called_client_id);
    var running = try app.start(io);
    defer running.stop() catch {};
    try std.testing.expect(!std.mem.eql(
        u8,
        &window.state.capability,
        &second_window.state.capability,
    ));

    const pages = [_]struct {
        window: Window,
        content: []const u8,
    }{
        .{ .window = window, .content = "test page" },
        .{ .window = second_window, .content = "second page" },
    };
    for (pages) |page| {
        var target: [capability_len + 2]u8 = undefined;
        var response: [512]u8 = undefined;
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/", .{
                page.window.state.capability,
            }),
            page.content,
            &response,
        );
        try std.testing.expect(std.mem.indexOf(u8, bytes, "HTTP/1.1 200 OK") != null);
    }
    {
        var target: [capability_len + 10]u8 = undefined;
        var response: [8192]u8 = undefined;
        const enabled = "globalThis.__zigWebuiEvents=true;";
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/webui.js", .{
                window.state.capability,
            }),
            enabled,
            &response,
        );
        try std.testing.expect(std.mem.indexOf(u8, bytes, enabled) != null);
    }
    {
        var target: [capability_len + 2]u8 = undefined;
        var response: [1024]u8 = undefined;
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/", .{
                directory_window.state.capability,
            }),
            "directory page",
            &response,
        );
        try std.testing.expect(std.mem.indexOf(
            u8,
            bytes,
            "Content-Type: text/html; charset=utf-8",
        ) != null);
    }
    {
        var target: [capability_len + 20]u8 = undefined;
        var response: [512]u8 = undefined;
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/%2e%2e/secret.txt", .{
                directory_window.state.capability,
            }),
            "\r\n\r\n",
            &response,
        );
        try std.testing.expect(std.mem.indexOf(
            u8,
            bytes,
            "HTTP/1.1 404 Not Found",
        ) != null);
        try std.testing.expect(std.mem.indexOf(u8, bytes, "not public") == null);
    }
    {
        var target: [capability_len + 17]u8 = undefined;
        var response: [512]u8 = undefined;
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/hello?name=zig", .{
                custom_window.state.capability,
            }),
            "hello?name=zig",
            &response,
        );
        try std.testing.expect(std.mem.indexOf(
            u8,
            bytes,
            "Content-Type: text/plain; charset=utf-8",
        ) != null);
    }
    {
        var target: [capability_len + 13]u8 = undefined;
        var response: [512]u8 = undefined;
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/index.html", .{
                window.state.capability,
            }),
            "\r\n\r\n",
            &response,
        );
        try std.testing.expect(std.mem.indexOf(
            u8,
            bytes,
            "HTTP/1.1 404 Not Found",
        ) != null);
    }
    const first_url = try window.url(&running, gpa);
    defer gpa.free(first_url);
    const second_url = try second_window.url(&running, gpa);
    defer gpa.free(second_url);
    try std.testing.expect(!std.mem.eql(u8, first_url, second_url));
    const opened_external_url = try external_window.url(&running, gpa);
    defer gpa.free(opened_external_url);
    try std.testing.expectEqualStrings(external_url, opened_external_url);
    const external_bridge_url = try external_window.bridgeUrl(&running, gpa);
    defer gpa.free(external_bridge_url);
    try std.testing.expect(std.mem.endsWith(
        u8,
        external_bridge_url,
        "/webui.js",
    ));
    try std.testing.expect(std.mem.indexOf(
        u8,
        external_bridge_url,
        &external_window.state.capability,
    ) != null);
    {
        var target: [capability_len + 10]u8 = undefined;
        var response: [8192]u8 = undefined;
        const disabled = "globalThis.__zigWebuiEvents=false;";
        const bytes = try getTestPath(
            running.inner.address,
            io,
            try std.fmt.bufPrint(&target, "/{s}/webui.js", .{
                external_window.state.capability,
            }),
            disabled,
            &response,
        );
        try std.testing.expect(std.mem.indexOf(u8, bytes, disabled) != null);
    }

    try std.testing.expectError(
        error.WebSocketUpgradeFailed,
        connectTestWebSocketOrigin(
            running.inner.address,
            io,
            &window.state.capability,
            "https://attacker.example",
        ),
    );
    {
        const external_client = try connectTestWebSocketOrigin(
            running.inner.address,
            io,
            &external_window.state.capability,
            "http://external.example",
        );
        defer external_client.close(io);
        try external_client.shutdown(io, .both);
        try std.Io.sleep(io, .fromMilliseconds(20), .awake);
    }

    {
        const unauthenticated = try connectTestWebSocket(
            running.inner.address,
            io,
            &window.state.capability,
        );
        defer unauthenticated.close(io);
        var rejected_response: [125]u8 = undefined;
        try std.testing.expect(!try authenticateTestClient(
            unauthenticated,
            io,
            gpa,
            window.state.token,
            "ffffffffffffffffffffffffffffffff",
            &rejected_response,
        ));
        try unauthenticated.shutdown(io, .both);
        try std.Io.sleep(io, .fromMilliseconds(20), .awake);
        try std.testing.expect(!app.closed.load(.acquire));
    }

    const client = try connectTestWebSocket(
        running.inner.address,
        io,
        &window.state.capability,
    );
    defer client.close(io);
    var response_payload: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        client,
        io,
        gpa,
        window.state.token,
        &window.state.capability,
        &response_payload,
    ));
    {
        const rejected = try connectTestWebSocket(
            running.inner.address,
            io,
            &window.state.capability,
        );
        defer rejected.close(io);
        var rejected_payload: [125]u8 = undefined;
        try std.testing.expect(!try authenticateTestClient(
            rejected,
            io,
            gpa,
            window.state.token,
            &window.state.capability,
            &rejected_payload,
        ));
    }

    var packet: std.ArrayList(u8) = .empty;
    defer packet.deinit(gpa);
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .command = .click,
    }, "primary");
    try sendClientFrame(client, io, packet.items);
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .command = .navigation,
    }, "http://localhost/next");
    try sendClientFrame(client, io, packet.items);
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
    try std.testing.expect(primary_events.connected.load(.acquire));
    try std.testing.expect(primary_events.clicked.load(.acquire));
    try std.testing.expect(primary_events.navigated.load(.acquire));
    try std.testing.expect(!secondary_events.connected.load(.acquire));
    const targeted_client: Client = .{
        .state = window.state,
        .client_id = called_client_id.load(.acquire),
    };
    try std.testing.expect(targeted_client.id() != 0);
    try std.testing.expect(targeted_client.isConnected(io));

    const second_client = try connectTestWebSocket(
        running.inner.address,
        io,
        &second_window.state.capability,
    );
    defer second_client.close(io);
    var second_response: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        second_client,
        io,
        gpa,
        second_window.state.token,
        &second_window.state.capability,
        &second_response,
    ));
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = second_window.state.token,
        .command = .click,
    }, "secondary\x00");
    try sendClientFrame(second_client, io, packet.items);
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = second_window.state.token,
        .id = 10,
        .command = .call,
    }, "greet\x003\x00Zig\x00");
    try sendClientFrame(second_client, io, packet.items);
    const isolated_reply = try protocol.decode(try readServerFrame(
        second_client,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(@as(usize, 0), isolated_reply.payload.len);
    try std.testing.expect(secondary_events.connected.load(.acquire));
    try std.testing.expect(secondary_events.clicked.load(.acquire));
    try std.testing.expect(!secondary_events.navigated.load(.acquire));

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
        error.InvalidScript,
        targeted_client.run(io, ""),
    );
    try targeted_client.run(io, "globalThis.quickResult = 42");
    const quick = try protocol.decode(try readServerFrame(
        client,
        io,
        &response_payload,
    ));
    try std.testing.expectEqual(protocol.Command.js_quick, quick.header.command);
    try std.testing.expectEqualStrings(
        "globalThis.quickResult = 42",
        quick.payload,
    );

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
    try std.testing.expect(!app.closed.load(.acquire));
    try second_client.shutdown(io, .both);
    try running.wait();
    try std.testing.expect(primary_events.disconnected.load(.acquire));
    try std.testing.expect(secondary_events.disconnected.load(.acquire));
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
        .content = .{ .html = "multi-client test" },
        .max_clients = 2,
        .max_pending_evals = 2,
    });
    var called_client_id: std.atomic.Value(u64) = .init(0);
    try window.bind("greet", integrationHandler, &called_client_id);
    var running = try app.start(io);
    defer running.stop() catch {};

    const first_stream = try connectTestWebSocket(
        running.inner.address,
        io,
        &window.state.capability,
    );
    defer first_stream.close(io);
    var first_response: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        first_stream,
        io,
        gpa,
        window.state.token,
        &window.state.capability,
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

    const second_stream = try connectTestWebSocket(
        running.inner.address,
        io,
        &window.state.capability,
    );
    defer second_stream.close(io);
    var second_response: [125]u8 = undefined;
    try std.testing.expect(try authenticateTestClient(
        second_stream,
        io,
        gpa,
        window.state.token,
        &window.state.capability,
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
        const rejected = try connectTestWebSocket(
            running.inner.address,
            io,
            &window.state.capability,
        );
        defer rejected.close(io);
        var rejected_response: [125]u8 = undefined;
        try std.testing.expect(!try authenticateTestClient(
            rejected,
            io,
            gpa,
            window.state.token,
            &window.state.capability,
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

    try std.testing.expectError(error.InvalidScript, window.run(io, ""));
    try std.testing.expectEqual(
        @as(usize, 2),
        try window.run(io, "globalThis.broadcastQuick = true"),
    );
    const first_quick = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    const second_quick = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(protocol.Command.js_quick, first_quick.header.command);
    try std.testing.expectEqual(protocol.Command.js_quick, second_quick.header.command);
    try std.testing.expectEqualStrings(first_quick.payload, second_quick.payload);

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

    try std.testing.expectEqual(@as(usize, 2), try window.navigate(io, "/all"));
    const first_broadcast_navigation = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    const second_broadcast_navigation = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(
        protocol.Command.navigation,
        first_broadcast_navigation.header.command,
    );
    try std.testing.expectEqualStrings("/all", first_broadcast_navigation.payload);
    try std.testing.expectEqual(
        protocol.Command.navigation,
        second_broadcast_navigation.header.command,
    );
    try std.testing.expectEqualStrings("/all", second_broadcast_navigation.payload);

    try std.testing.expectEqual(
        @as(usize, 2),
        try window.sendRaw(io, "receiveRaw", &raw_data),
    );
    const first_broadcast_raw = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    const second_broadcast_raw = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(protocol.Command.raw, first_broadcast_raw.header.command);
    try std.testing.expectEqual(protocol.Command.raw, second_broadcast_raw.header.command);
    try std.testing.expectEqualSlices(
        u8,
        first_broadcast_raw.payload,
        second_broadcast_raw.payload,
    );

    try std.testing.expectEqual(@as(usize, 2), try window.close(io));
    const first_broadcast_close = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    const second_broadcast_close = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(
        protocol.Command.close,
        first_broadcast_close.header.command,
    );
    try std.testing.expectEqual(
        protocol.Command.close,
        second_broadcast_close.header.command,
    );

    var broadcast_eval = io.async(Window.evalAll, .{
        window,
        io,
        "return 21",
        16,
        std.Io.Duration.fromSeconds(1),
    });
    const first_broadcast_eval = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    const second_broadcast_eval = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = first_broadcast_eval.header.id,
        .command = .js,
    }, "\x0021\x00");
    try sendClientFrame(first_stream, io, packet.items);
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = second_broadcast_eval.header.id,
        .command = .js,
    }, "\x01failed\x00");
    try sendClientFrame(second_stream, io, packet.items);

    var broadcast_results = try broadcast_eval.await(io);
    defer broadcast_results.deinit();
    try std.testing.expectEqual(@as(usize, 2), broadcast_results.items.len);
    for (broadcast_results.items) |result| {
        if (result.client.id() == first.id()) {
            switch (result.outcome) {
                .value => |value| try std.testing.expectEqualStrings("21", value),
                else => return error.UnexpectedBroadcastResult,
            }
        } else if (result.client.id() == second.id()) {
            switch (result.outcome) {
                .javascript_error => |message| {
                    try std.testing.expectEqualStrings("failed", message);
                },
                else => return error.UnexpectedBroadcastResult,
            }
        } else {
            return error.UnexpectedBroadcastClient;
        }
    }

    var timeout_broadcast = io.async(Window.evalAll, .{
        window,
        io,
        "return 'late'",
        16,
        std.Io.Duration.fromMilliseconds(50),
    });
    const first_timeout_eval = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));
    _ = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = first_timeout_eval.header.id,
        .command = .js,
    }, "\x00ready\x00");
    try sendClientFrame(first_stream, io, packet.items);

    var timeout_results = try timeout_broadcast.await(io);
    defer timeout_results.deinit();
    for (timeout_results.items) |result| {
        if (result.client.id() == first.id()) {
            switch (result.outcome) {
                .value => |value| try std.testing.expectEqualStrings("ready", value),
                else => return error.UnexpectedBroadcastResult,
            }
        } else if (result.client.id() == second.id()) {
            switch (result.outcome) {
                .failed => |err| try std.testing.expectEqual(error.Timeout, err),
                else => return error.UnexpectedBroadcastResult,
            }
        } else {
            return error.UnexpectedBroadcastClient;
        }
    }

    var first_eval_buffer: [16]u8 = undefined;
    var first_eval = io.async(Client.eval, .{
        first,
        io,
        "return 3",
        &first_eval_buffer,
        std.Io.Duration.fromSeconds(1),
    });
    const first_eval_request = try protocol.decode(try readServerFrame(
        first_stream,
        io,
        &first_response,
    ));

    var second_eval_buffer: [16]u8 = undefined;
    var second_eval = io.async(Client.eval, .{
        second,
        io,
        "return 7",
        &second_eval_buffer,
        std.Io.Duration.fromSeconds(1),
    });
    const second_eval_request = try protocol.decode(try readServerFrame(
        second_stream,
        io,
        &second_response,
    ));
    try std.testing.expectEqual(
        protocol.Command.js,
        first_eval_request.header.command,
    );
    try std.testing.expectEqual(protocol.Command.js, second_eval_request.header.command);
    try std.testing.expect(first_eval_request.header.id != second_eval_request.header.id);

    var rejected_eval_buffer: [16]u8 = undefined;
    try std.testing.expectError(error.TooManyPendingEvals, second.eval(
        io,
        "return 11",
        &rejected_eval_buffer,
        std.Io.Duration.fromSeconds(1),
    ));

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
    try std.testing.expectError(error.ConnectionClosed, first_eval.await(io));

    packet.clearRetainingCapacity();
    try protocol.append(&packet, gpa, .{
        .token = window.state.token,
        .id = second_eval_request.header.id,
        .command = .js,
    }, "\x007\x00");
    try sendClientFrame(second_stream, io, packet.items);
    switch (try second_eval.await(io)) {
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
