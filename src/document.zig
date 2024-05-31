const std = @import("std");
const lsp = @import("lsp.zig");

pub const Document = struct {
    allocator: std.mem.Allocator,
    /// Slice pointing to the document's text.
    text: []u8,
    /// Slice pointing to the memory where the text is stored.
    data: []u8,

    pub fn init(allocator: std.mem.Allocator, content: []const u8) !Document {
        const data = try allocator.alloc(u8, content.len + content.len / 3);
        std.mem.copyForwards(u8, data, content);
        const text = data[0..content.len];
        return Document{
            .allocator = allocator,
            .data = data,
            .text = text,
        };
    }

    pub fn deinit(self: Document) void {
        self.allocator.free(self.data);
    }

    pub fn update(self: *Document, text: []const u8, range: lsp.Range) !void {
        const range_start = posToIdx(self.text, range.start) orelse self.text.len;
        const range_end = posToIdx(self.text, range.end) orelse self.text.len;
        const range_len = range_end - range_start;
        const new_len = self.text.len + text.len - range_len;
        const old_len = self.text.len;
        if (new_len > self.data.len) {
            self.data = try self.allocator.realloc(self.data, new_len + new_len / 3);
        }

        if (range_len > text.len) {
            std.mem.copyForwards(u8, self.data[range_start..], text);
            std.mem.copyForwards(u8, self.data[range_start + text.len ..], self.data[range_end..]);
        } else if (range_len < text.len) {
            std.mem.copyBackwards(u8, self.data[range_end + (text.len - range_len) ..], self.data[range_end..old_len]);
            std.mem.copyForwards(u8, self.data[range_start..], text);
        } else {
            std.mem.copyForwards(u8, self.data[range_start..range_end], text);
        }

        self.text = self.data[0..new_len];
    }

    fn idxToPos(text: []const u8, idx: usize) ?lsp.Position {
        if (idx > text.len) {
            return null;
        }
        const line = std.mem.count(u8, text[0..idx], "\n");
        if (line == 0) {
            return .{ .line = 0, .character = idx };
        }
        const col = idx - (std.mem.lastIndexOf(u8, text[0..idx], "\n") orelse 0) - 1;
        return .{ .line = line, .character = col };
    }

    fn posToIdx(text: []const u8, pos: lsp.Position) ?usize {
        var offset: usize = 0;
        var i: usize = 0;
        while (i < pos.line) : (i += 1) {
            if (std.mem.indexOf(u8, text[offset..], "\n")) |idx| {
                offset += idx + 1;
            } else return null;
        }
        return offset + pos.character;
    }

    pub fn getLine(self: Document, pos: lsp.Position) ?[]const u8 {
        const idx = posToIdx(self.text, pos) orelse return null;
        const start = if (std.mem.lastIndexOfScalar(u8, self.text[0..idx], '\n')) |s| s + 1 else 0;
        const end = idx + (std.mem.indexOfScalar(u8, self.text[idx..], '\n') orelse self.text.len - idx);

        return self.text[start..end];
    }
};

test "addText" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "hello world");
    defer doc.deinit();

    try doc.update(",", .{
        .start = .{ .line = 0, .character = 5 },
        .end = .{ .line = 0, .character = 5 },
    });
    try std.testing.expectEqualStrings("hello, world", doc.text);
}

test "addTextAtEnd" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "hello world");
    defer doc.deinit();

    try doc.update("!", .{
        .start = .{ .line = 0, .character = 11 },
        .end = .{ .line = 0, .character = 11 },
    });
    try std.testing.expectEqualStrings("hello world!", doc.text);
}

test "addTextAtStart" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "ello world");
    defer doc.deinit();

    try doc.update("H", .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 0 },
    });
    try std.testing.expectEqualStrings("Hello world", doc.text);
}

test "ChangeText" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "hello world");
    defer doc.deinit();
    try doc.update("H", .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 1 },
    });
    try std.testing.expectEqualStrings("Hello world", doc.text);
}

test "RemoveText" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "Hello world");
    defer doc.deinit();
    try doc.update("", .{
        .start = .{ .line = 0, .character = 5 },
        .end = .{ .line = 0, .character = 6 },
    });
    try std.testing.expectEqualStrings("Helloworld", doc.text);
}

test "RemoveTextAtStart" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "Hello world");
    defer doc.deinit();
    try doc.update("", .{
        .start = .{ .line = 0, .character = 0 },
        .end = .{ .line = 0, .character = 1 },
    });
    try std.testing.expectEqualStrings("ello world", doc.text);
}

test "RemoveTextAtEnd" {
    const allocator = std.testing.allocator;
    var doc = try Document.init(allocator, "Hello world");
    defer doc.deinit();
    try doc.update("", .{
        .start = .{ .line = 0, .character = 10 },
        .end = .{ .line = 0, .character = 11 },
    });
    try std.testing.expectEqualStrings("Hello worl", doc.text);
}
