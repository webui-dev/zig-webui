const std = @import("std");
const webui = @import("webui");

pub fn main() !void {
    var new_window = webui.newWindow();

    _ = new_window.show(my_html);

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

    const res_buf = for (response, 0..) |value, i| {
        if (value == 0) {
            break response[0..i];
        }
    } else response[0..];

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

const my_html =
    \\<!doctype html>
    \\<html>
    \\	<head>
    \\		<meta charset="UTF-8\" />
    \\		<script src="webui.js"></script>
    \\		<title>Call JavaScript from C Example</title>
    \\		<style>
    \\			body {
    \\				font-family: "Arial", sans-serif;
    \\				color: white;
    \\				background: linear-gradient(
    \\					to right,
    \\					#507d91,
    \\					#1c596f,
    \\					#022737
    \\				);
    \\				text-align: center;
    \\				font-size: 18px;
    \\			}
    \\			button,
    \\			input {
    \\				padding: 10px;
    \\				margin: 10px;
    \\				border-radius: 3px;
    \\				border: 1px solid #ccc;
    \\				box-shadow: 0 3px 5px rgba(0, 0, 0, 0.1);
    \\				transition: 0.2s;
    \\			}
    \\			button {
    \\				background: #3498db;
    \\				color: #fff;
    \\				cursor: pointer;
    \\				font-size: 16px;
    \\			}
    \\			h1 {
    \\				text-shadow: -7px 10px 7px rgb(67 57 57 / 76%);
    \\			}
    \\			button:hover {
    \\				background: #c9913d;
    \\			}
    \\			input:focus {
    \\				outline: none;
    \\				border-color: #3498db;
    \\			}
    \\		</style>
    \\	</head>
    \\	<body>
    \\		<h1>WebUI - Call JavaScript from zig</h1>
    \\		<br />
    \\		<h1 id="count">0</h1>
    \\		<br />
    \\		<button id="MyButton1">Manual Count</button>
    \\		<br />
    \\		<button id="MyTest" OnClick="AutoTest();">
    \\			Auto Count (Every 10ms)
    \\		</button>
    \\		<br />
    \\		<button id="MyButton2">Exit</button>
    \\		<script>
    \\			let count = 0;
    \\			function GetCount() {
    \\				return count;
    \\			}
    \\			function SetCount(number) {
    \\				document.getElementById("count").innerHTML = number;
    \\				count = number;
    \\			}
    \\          let interval = -1;
    \\			function AutoTest(number) {
    \\              if(interval == -1){
    \\				    interval = setInterval(function () {
    \\					    webui.call("MyButton1");
    \\				    }, 10);
    \\              } else {
    \\                  clearInterval(interval);
    \\                  interval=-1;
    \\              }
    \\			}
    \\		</script>
    \\	</body>
    \\</html>
;
