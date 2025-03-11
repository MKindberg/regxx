const std = @import("std");
const lsp = @import("lsp");
const builtin = @import("builtin");

const Regex = @import("regex").Regex;

pub const std_options = std.Options{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = lsp.log
};

const Lsp = lsp.Lsp(void);
pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const server_data = lsp.types.ServerData{
        .serverInfo = .{
            .name = "regxx",
            .version = @embedFile("version"),
        },
    };
    var server = lsp.Lsp(void).init(allocator, server_data);
    defer server.deinit();

    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleHover(p: Lsp.HoverParameters) ?[]const u8 {
    const line = p.context.document.getLine(p.position).?;
    const char = p.position.character;
    const in_str = std.mem.count(u8, line[0..char], "\"") % 2 == 1 and
        std.mem.count(u8, line[char..], "\"") > 0;

    if (in_str) {
        const start = std.mem.lastIndexOfScalar(u8, line[0..char], '"').? + 1;
        const end = std.mem.indexOfScalar(u8, line[char..], '"').? + char;
        const regex = Regex.initLeaky(p.arena, line[start..end]) catch return null;

        var buf = std.ArrayList(u8).init(p.arena);
        regex.print(buf.writer()) catch return null;
        return buf.items;
    }
    return null;
}
