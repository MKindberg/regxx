const std = @import("std");
const State = @import("analysis.zig").State;
const lsp = @import("lsp");
const lsp_types = @import("lsp").types;

const Logger = @import("logger.zig").Logger;

const builtin = @import("builtin");

pub const std_options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = Logger.log,
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/regEx-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    var state = State{};

    const server_data = lsp_types.ServerData{
        .capabilities = .{
            .textDocumentSync = 2,
            .hoverProvider = true,
        },
        .serverInfo = .{
            .name = "regEx-ls",
            .version = "0.1.0",
        },
    };
    var server = lsp.Lsp(State).init(allocator, server_data, &state);
    defer server.deinit();

    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(allocator: std.mem.Allocator, context: lsp.Lsp(State).Context, request: lsp_types.Request.Hover.Params, id: i32) void {
    if (State.hover(allocator, id, context.document, request.position)) |response| {
        defer allocator.free(response.result.contents);
        lsp.writeResponse(allocator, response) catch unreachable;

        std.log.info("Sent Hover response", .{});
    }
}
