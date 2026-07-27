//! Pure Zig WebUI.

pub const App = @import("app.zig").App;
pub const Window = @import("app.zig").Window;
pub const Client = @import("app.zig").Client;
pub const Running = @import("app.zig").Running;
pub const Call = @import("app.zig").Call;
pub const Handler = @import("app.zig").Handler;
pub const EvalResult = @import("app.zig").EvalResult;
pub const BroadcastEvalOutcome = @import("app.zig").BroadcastEvalOutcome;
pub const BroadcastEval = @import("app.zig").BroadcastEval;
pub const BroadcastEvalResults = @import("app.zig").BroadcastEvalResults;
pub const protocol = @import("protocol.zig");

test {
    _ = @import("app.zig");
    _ = protocol;
}
