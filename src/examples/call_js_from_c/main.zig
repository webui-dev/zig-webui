const std = @import("std");
const webui = @import("webui");

const html = @embedFile("index.html");

pub fn main() !void {
    var new_window = webui.newWindow();

    _ = new_window.show(html);

    _ = new_window.bind("MyButton1", count);
    _ = new_window.bind("MyButton2", exit);

    webui.wait();

    webui.clean();
}

fn count(e: webui.Event) void {
    var new_e = e;
    var response: [64]u8 = undefined;

    var win = new_e.getWindow();
    if (!win.script("return GetCount();", 0, &response)) {
        if (!win.isShown()) {
            std.debug.print("window closed\n", .{});
        } else {
            std.debug.print("js error:{s}\n", .{response});
        }
    }

    const res_buf = response[0..std.mem.len(@as([*:0]u8, @ptrCast(&response)))];

    var tmp_count = std.fmt.parseInt(i32, res_buf, 10) catch |err| blk: {
        std.log.err("error is {}", .{err});
        break :blk -50;
    };

    tmp_count += 1;

    var js: [64]u8 = std.mem.zeroes([64]u8);
    const buf = std.fmt.bufPrint(&js, "SetCount({});", .{tmp_count}) catch unreachable;

    win.run(buf);
}

fn exit(e: webui.Event) void {
    _ = e;
    webui.exit();
}
