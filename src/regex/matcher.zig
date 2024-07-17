const std = @import("std");
const types = @import("types.zig");
const Regex = @import("regex.zig").Regex;

pub fn matches(self: Regex, string: []const u8) bool {
    const tokens = self.tokens.items;
    if (tokens.len == 0) return false;
    if (tokens[0].token == .Anchor and tokens[0].token.Anchor == .Start) {
        return matchesRec(tokens[1..], string);
    }
    return matchesRec(tokens, string);
}

fn matchesRec(tokens: []const types.Token, string: []const u8) bool {
    if (tokens.len == 0 or tokens.len == 1 and tokens[0].token == .Anchor and tokens[0].token.Anchor == .End) return string.len == 0;
    if (string.len == 0) return false;
    switch (tokens[0].token) {
        .Literal => |l| {
            if (std.mem.startsWith(u8, string, l)) return matchesRec(tokens[1..], string[l.len..]);
            return false;
        },
        .Any => return matchesRec(tokens[1..], string[1..]),
        .CharacterGroup => |c| {
            if (matchesCharacterGroup(c, string[0])) return matchesRec(tokens[1..], string[1..]);
            return false;
        },
        .NegCharacterGroup => |c| {
            if (!matchesCharacterGroup(c, string[0])) return matchesRec(tokens[1..], string[1..]);
            return false;
        },
        .CharacterClass => |c| {
            switch (c) {
                .Control => if (std.ascii.isControl(string[0])) return matchesRec(tokens[1..], string[1..]),
                .Digit => if (std.ascii.isDigit(string[0])) return matchesRec(tokens[1..], string[1..]),
                .NotDigit => if (!std.ascii.isDigit(string[0])) return matchesRec(tokens[1..], string[1..]),
                .Space => if (std.ascii.isWhitespace(string[0])) return matchesRec(tokens[1..], string[1..]),
                .NotSpace => if (!std.ascii.isWhitespace(string[0])) return matchesRec(tokens[1..], string[1..]),
                .Word => if (std.ascii.isAlphanumeric(string[0]) or string[0] == '_') return matchesRec(tokens[1..], string[1..]),
                .NotWord => if (!(std.ascii.isAlphanumeric(string[0]) or string[0] == '_')) return matchesRec(tokens[1..], string[1..]),
                .HexDigit => if (std.ascii.isHex(string[0])) return matchesRec(tokens[1..], string[1..]),
                .Octal => if ('0' <= string[0] and string[0] <= '7') return matchesRec(tokens[1..], string[1..]),
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
            _ = s;
            @panic("special not yet implemented");
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
