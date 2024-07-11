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

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/regxx/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    const server_data = lsp.types.ServerData{
        .capabilities = .{
            .hoverProvider = true,
        },
        .serverInfo = .{
            .name = "regxx",
            .version = "0.1.0",
        },
    };
    var server = lsp.Lsp(void).init(allocator, server_data);
    defer server.deinit();

    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(arena: std.mem.Allocator, context: *Lsp.Context, position: lsp.types.Position) ?[]const u8 {
    const line = context.document.getLine(position).?;
    const char = position.character;
    const in_str = std.mem.count(u8, line[0..char], "\"") % 2 == 1 and
        std.mem.count(u8, line[char..], "\"") > 0;

    if (in_str) {
        const start = std.mem.lastIndexOfScalar(u8, line[0..char], '"').? + 1;
        const end = std.mem.indexOfScalar(u8, line[char..], '"').? + char;
        const regex = Regex.initLeaky(arena, line[start..end]) catch return null;

        var buf = std.ArrayList(u8).init(arena);
        regex.print(buf.writer()) catch return null;
        return buf.items;
    }
    return null;
}
