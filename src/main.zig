const std = @import("std");
const lsp = @import("lsp");
const builtin = @import("builtin");

const Logger = @import("logger.zig").Logger;
const Regex = @import("regex.zig").Regex;

pub const std_options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = Logger.log,
};

const Lsp = lsp.Lsp(void);
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/regEx-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    const server_data = lsp.types.ServerData{
        .capabilities = .{
            .hoverProvider = true,
        },
        .serverInfo = .{
            .name = "regEx-ls",
            .version = "0.1.0",
        },
    };
    var server = lsp.Lsp(void).init(allocator, server_data);
    defer server.deinit();

    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(allocator: std.mem.Allocator, context: *Lsp.Context, id: i32, position: lsp.types.Position) void {
    const line = context.document.getLine(position).?;
    const char = position.character;
    const in_str = std.mem.count(u8, line[0..char], "\"") % 2 == 1 and
        std.mem.count(u8, line[char..], "\"") > 0;

    if (in_str) {
        const start = std.mem.lastIndexOfScalar(u8, line[0..char], '"').? + 1;
        const end = std.mem.indexOfScalar(u8, line[char..], '"').? + char;
        const regex = Regex.init(allocator, line[start..end]) catch return;
        defer regex.deinit();

        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        regex.print(buf.writer()) catch return;
        const response = lsp.types.Response.Hover.init(id, buf.items);
        lsp.writeResponse(allocator, response) catch unreachable;
        std.log.info("Sent Hover response", .{});
    }
}
