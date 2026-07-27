const std = @import("std");

pub const signature = 0xdd;
pub const header_len = 8;
pub const max_args = 16;

pub const Command = enum(u8) {
    js = 0xfe,
    js_quick = 0xfd,
    click = 0xfc,
    navigation = 0xfb,
    close = 0xfa,
    call = 0xf9,
    raw = 0xf8,
    check_token = 0xf5,
    _,
};

pub const Header = struct {
    token: u32,
    id: u16 = 0,
    command: Command,
};

pub const Packet = struct {
    header: Header,
    payload: []const u8,
};

pub const DecodeError = error{ InvalidPacket, UnknownCommand };

pub fn decode(bytes: []const u8) DecodeError!Packet {
    if (bytes.len < header_len or bytes[0] != signature) return error.InvalidPacket;
    const command: Command = @enumFromInt(bytes[7]);
    switch (command) {
        .js,
        .js_quick,
        .click,
        .navigation,
        .close,
        .call,
        .raw,
        .check_token,
        => {},
        _ => return error.UnknownCommand,
    }
    return .{
        .header = .{
            .token = std.mem.readInt(u32, bytes[1..][0..4], .little),
            .id = std.mem.readInt(u16, bytes[5..][0..2], .little),
            .command = command,
        },
        .payload = bytes[header_len..],
    };
}

pub fn append(
    out: *std.ArrayList(u8),
    gpa: std.mem.Allocator,
    header: Header,
    payload: []const u8,
) !void {
    const start = out.items.len;
    try out.resize(gpa, start + header_len);
    out.items[start] = signature;
    std.mem.writeInt(u32, out.items[start + 1 ..][0..4], header.token, .little);
    std.mem.writeInt(u16, out.items[start + 5 ..][0..2], header.id, .little);
    out.items[start + 7] = @intFromEnum(header.command);
    try out.appendSlice(gpa, payload);
}

pub const CallPayload = struct {
    name: []const u8,
    args: [max_args][]const u8 = undefined,
    count: usize = 0,

    pub fn slice(self: *const CallPayload) []const []const u8 {
        return self.args[0..self.count];
    }
};

pub fn decodeCall(payload: []const u8) DecodeError!CallPayload {
    const name_end = std.mem.indexOfScalar(u8, payload, 0) orelse
        return error.InvalidPacket;
    const lengths_start = name_end + 1;
    const lengths_relative_end = std.mem.indexOfScalar(
        u8,
        payload[lengths_start..],
        0,
    ) orelse return error.InvalidPacket;
    const lengths_end = lengths_start + lengths_relative_end;

    var result: CallPayload = .{ .name = payload[0..name_end] };
    var data_at = lengths_end + 1;
    if (lengths_end != lengths_start) {
        var lengths = std.mem.splitScalar(
            u8,
            payload[lengths_start..lengths_end],
            ';',
        );
        while (lengths.next()) |text| {
            if (result.count == max_args or text.len == 0) return error.InvalidPacket;
            const len = std.fmt.parseInt(usize, text, 10) catch
                return error.InvalidPacket;
            if (len > payload.len - data_at or
                payload.len - data_at - len < 1 or
                payload[data_at + len] != 0)
            {
                return error.InvalidPacket;
            }
            result.args[result.count] = payload[data_at .. data_at + len];
            result.count += 1;
            data_at += len + 1;
        }
    }
    if (data_at != payload.len) return error.InvalidPacket;
    return result;
}

pub fn decodeEventText(payload: []const u8) DecodeError![]const u8 {
    var text = payload;
    if (text.len > 0 and text[text.len - 1] == 0)
        text = text[0 .. text.len - 1];
    if (text.len == 0 or
        std.mem.indexOfScalar(u8, text, 0) != null or
        !std.unicode.utf8ValidateSlice(text))
    {
        return error.InvalidPacket;
    }
    return text;
}

test "packet and call payload decode" {
    const gpa = std.testing.allocator;
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(gpa);
    try append(&bytes, gpa, .{
        .token = 0x12345678,
        .id = 7,
        .command = .call,
    }, "sum\x001;4\x007\x001234\x00");

    const packet = try decode(bytes.items);
    try std.testing.expectEqual(@as(u32, 0x12345678), packet.header.token);
    try std.testing.expectEqual(@as(u16, 7), packet.header.id);

    const call = try decodeCall(packet.payload);
    try std.testing.expectEqualStrings("sum", call.name);
    try std.testing.expectEqual(@as(usize, 2), call.count);
    try std.testing.expectEqualStrings("7", call.args[0]);
    try std.testing.expectEqualStrings("1234", call.args[1]);
    try std.testing.expectEqualStrings("button", try decodeEventText("button"));
    try std.testing.expectEqualStrings("button", try decodeEventText("button\x00"));
}

test "untrusted packets are rejected" {
    try std.testing.expectError(error.InvalidPacket, decode(""));
    try std.testing.expectError(
        error.UnknownCommand,
        decode(&.{ signature, 0, 0, 0, 0, 0, 0, 1 }),
    );
    try std.testing.expectError(
        error.InvalidPacket,
        decodeCall("call\x001;4\x007\x00123"),
    );
    try std.testing.expectError(
        error.InvalidPacket,
        decodeCall("call\x00\x00trailing"),
    );
    try std.testing.expectError(error.InvalidPacket, decodeEventText(""));
    try std.testing.expectError(
        error.InvalidPacket,
        decodeEventText("button\x00trailing"),
    );
    try std.testing.expectError(
        error.InvalidPacket,
        decodeEventText(&.{0xff}),
    );
}
