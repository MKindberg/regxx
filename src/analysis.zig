const std = @import("std");
const lsp_types = @import("lsp").types;
const Document = @import("lsp").Document;
const Regex = @import("regex.zig").Regex;

pub const State = struct {
    pub fn hover(allocator: std.mem.Allocator, id: i32, doc: Document, pos: lsp_types.Position) ?lsp_types.Response.Hover {
        const line = doc.getLine(pos).?;
        const char = pos.character;
        const in_str = std.mem.count(u8, line[0..char], "\"") % 2 == 1 and
            std.mem.count(u8, line[char..], "\"") > 0;

        if (in_str) {
            const start = std.mem.lastIndexOfScalar(u8, line[0..char], '"').? + 1;
            const end = std.mem.indexOfScalar(u8, line[char..], '"').? + char;
            const regex= Regex.init(allocator, line[start..end]) catch return null;
            defer regex.deinit();

            var buf = std.ArrayList(u8).init(allocator);
            defer buf.deinit();
            regex.print(buf.writer()) catch return null;
            const res = allocator.dupe(u8, buf.items) catch return null;
            return lsp_types.Response.Hover.init(id, res);
        } else return null;
    }
};
