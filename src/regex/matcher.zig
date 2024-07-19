const std = @import("std");
const types = @import("types.zig");
const Regex = @import("regex.zig").Regex;

pub fn matches(self: Regex, string: []const u8) bool {
    const tokens = self.tokens.items;
    if (tokens.len == 0) return false;
    if (tokens[0].token == .Anchor and tokens[0].token.Anchor == .Start) {
        return matchesRec(tokens[1..], string, 0);
    }
    return matchesRec(tokens, string, 0);
}

fn matchesRec(tokens: []const types.Token, string: []const u8, i: usize) bool {
    if (tokens.len == 0 or tokens.len == 1 and tokens[0].token == .Anchor and tokens[0].token.Anchor == .End) return string.len == i;
    if (string.len <= i) return false;
    switch (tokens[0].token) {
        .Literal => |l| {
            if (std.mem.startsWith(u8, string[i..], l)) return matchesRec(tokens[1..], string, i + l.len);
            return false;
        },
        .Any => return matchesRec(tokens[1..], string, i + 1),
        .CharacterGroup => |c| {
            if (matchesCharacterGroup(c, string[i])) return matchesRec(tokens[1..], string, i + 1);
            return false;
        },
        .NegCharacterGroup => |c| {
            if (!matchesCharacterGroup(c, string[i])) return matchesRec(tokens[1..], string, i + 1);
            return false;
        },
        .CharacterClass => |c| {
            switch (c) {
                .Control => if (std.ascii.isControl(string[i])) return matchesRec(tokens[1..], string, i + 1),
                .Digit => if (std.ascii.isDigit(string[i])) return matchesRec(tokens[1..], string, i + 1),
                .NotDigit => if (!std.ascii.isDigit(string[i])) return matchesRec(tokens[1..], string, i + 1),
                .Space => if (std.ascii.isWhitespace(string[i])) return matchesRec(tokens[1..], string, i + 1),
                .NotSpace => if (!std.ascii.isWhitespace(string[i])) return matchesRec(tokens[1..], string, i + 1),
                .Word => if (std.ascii.isAlphanumeric(string[i]) or string[i] == '_') return matchesRec(tokens[1..], string, i + 1),
                .NotWord => if (!(std.ascii.isAlphanumeric(string[i]) or string[i] == '_')) return matchesRec(tokens[1..], string, i + 1),
                .HexDigit => if (std.ascii.isHex(string[i])) return matchesRec(tokens[1..], string, i + 1),
                .Octal => if ('0' <= string[i] and string[i] <= '7') return matchesRec(tokens[1..], string, i + 1),
            }
        },
        .Quantifier => |q| {
            _ = q;
            @panic("quantifiers not yet implemented");
        },
        .Anchor => |a| {
            _ = a;
            @panic("anchor not yet implemented");
        },
        .Special => |s| {
            switch (s) {
                .Newline => if (string[i] == '\n') return matchesRec(tokens[1..], string, i + 1),
                .CarriageReturn => if (string[i] == '\r') return matchesRec(tokens[1..], string, i + 1),
                .Tab => if (string[i] == '\t') return matchesRec(tokens[1..], string, i + 1),
                .VerticalTab => if (string[i] == 11) return matchesRec(tokens[1..], string, i + 1),
                .FormFeed => if (string[i] == 12) return matchesRec(tokens[1..], string, i + 1),
            }
            return false;
        },
        .Group => |g| {
            _ = g;
            @panic("group not yet implemented");
        },
    }
    return false;
}

fn matchesCharacterGroup(c: types.CharacterGroupData, character: u8) bool {
    if (std.mem.indexOfScalar(u8, c.characters.items, character) != null) return true;
    for (c.ranges.items) |r| {
        if (r.start <= character and character <= r.end) return true;
    }
    return false;
}

test "matches literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "abc");
    try std.testing.expect(regex.matches("abc"));
}

test "matches any" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "..");
    try std.testing.expect(regex.matches("ab"));
    try std.testing.expect(regex.matches("bc"));
    try std.testing.expect(regex.matches("cd"));
}

test "matches character group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "[abce-h]");
    try std.testing.expect(regex.matches("a"));
    try std.testing.expect(regex.matches("b"));
    try std.testing.expect(regex.matches("c"));
    try std.testing.expect(!regex.matches("d"));
    try std.testing.expect(regex.matches("e"));
    try std.testing.expect(regex.matches("f"));
    try std.testing.expect(regex.matches("g"));
    try std.testing.expect(regex.matches("h"));
    try std.testing.expect(!regex.matches("i"));
}

test "matches neg character group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "[^abce-h]");
    try std.testing.expect(!regex.matches("a"));
    try std.testing.expect(!regex.matches("b"));
    try std.testing.expect(!regex.matches("c"));
    try std.testing.expect(regex.matches("d"));
    try std.testing.expect(!regex.matches("e"));
    try std.testing.expect(!regex.matches("f"));
    try std.testing.expect(!regex.matches("g"));
    try std.testing.expect(!regex.matches("h"));
    try std.testing.expect(regex.matches("i"));
}

test "matches character class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\\d
    );
    try std.testing.expect(regex.matches("2"));
    try std.testing.expect(regex.matches("9"));
    try std.testing.expect(!regex.matches("a"));

    const regex2 = try Regex.initLeaky(arena.allocator(),
        \\\x
    );
    try std.testing.expect(regex2.matches("2"));
    try std.testing.expect(regex2.matches("9"));
    try std.testing.expect(regex2.matches("a"));
    try std.testing.expect(regex2.matches("B"));
}

test "matches special" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a\nb
    );
    try std.testing.expect(regex.matches(
        \\a
        \\b
    ));
}
