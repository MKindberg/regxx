const std = @import("std");
const types = @import("types.zig");
const Regex = @import("regex.zig").Regex;

pub fn matches(self: Regex, string: []const u8) bool {
    const tokens = self.tokens.items;
    if (tokens.len == 0) return false;
    return matchesRec(tokens, string, 0);
}

fn matchesRec(tokens: []const types.Token, string: []const u8, idx: usize) bool {
    var i = idx;
    if (tokens.len == 0) return string.len == i;
    if (string.len == i and tokens.len == 1 and tokens[0].token == .Quantifier and tokens[0].token.Quantifier.min == 0) return true;
    if (tokens.len == 1 and tokens[0].token == .Anchor) {
        switch (tokens[0].token.Anchor) {
            .End, .EndOfLine => return string.len == i,
            .EndOfWord, .WordBoundary => return string.len == i and isWord(string[i - 1]),
            .NotWordBoundary => return i == 0 and !isWord(string[i - 1]),
            else => {},
        }
    }
    if (string.len <= i) return false;

    if (tokens[0].token == .Quantifier) {
        const q = tokens[0].token.Quantifier;
        for (0..q.min) |_| {
            if (i >= string.len) return false;
            if (matchesTok(q.token.token, string, i)) |steps| {
                i += steps;
            } else return false;
        }
        for (q.min..q.max) |_| {
            if (tokens.len == 1 and i == string.len) return true;
            if (tokens.len > 1 and i >= string.len) return false;
            if (matchesRec(tokens[1..], string, i)) {
                return true;
            } else if (matchesTok(q.token.token, string, i)) |steps| {
                i += steps;
            } else return false;
        }
        if (tokens.len == 1 and i == string.len) return true;
        if (tokens.len > 1) {
            if (matchesTok(tokens[1].token, string, i)) |steps| {
                return matchesRec(tokens[2..], string, i + steps);
            }
        }
        return false;
    }

    if (matchesTok(tokens[0].token, string, i)) |steps| return matchesRec(tokens[1..], string, i + steps);
    return false;
}

fn matchesTok(token: types.TokenType, string: []const u8, i: usize) ?usize {
    switch (token) {
        .Literal => |l| {
            if (std.mem.startsWith(u8, string[i..], l)) return l.len;
            return null;
        },
        .Any => return 1,
        .CharacterGroup => |c| {
            if (matchesCharacterGroup(c, string[i])) return 1;
            return null;
        },
        .NegCharacterGroup => |c| {
            if (!matchesCharacterGroup(c, string[i])) return 1;
            return null;
        },
        .CharacterClass => |c| {
            switch (c) {
                .Control => if (std.ascii.isControl(string[i])) return 1,
                .Digit => if (std.ascii.isDigit(string[i])) return 1,
                .NotDigit => if (!std.ascii.isDigit(string[i])) return 1,
                .Space => if (std.ascii.isWhitespace(string[i])) return 1,
                .NotSpace => if (!std.ascii.isWhitespace(string[i])) return 1,
                .Word => if (isWord(string[i])) return 1,
                .NotWord => if (!isWord(string[i])) return 1,
                .HexDigit => if (std.ascii.isHex(string[i])) return 1,
                .Octal => if ('0' <= string[i] and string[i] <= '7') return 1,
            }
        },
        .Quantifier => { // Handled in matchesRec
            unreachable;
        },
        .Anchor => |a| {
            switch (a) {
                .Start => if (i == 0) return 0,
                .End => unreachable, // handled at the top
                .StartOfLine => if (i == 0 or string[i - 1] == '\n') return 0,
                .EndOfLine => if (string[i] == '\n') return 0,
                .StartOfWord => if ((i == 0 or !isWord(string[i - 1])) and isWord(string[i])) return 0,
                .EndOfWord => if (isWord(string[i - 1]) and !isWord(string[i])) return 0,
                .WordBoundary => if (i == 0 and isWord(string[i]) or isWord(string[i - 1]) != isWord(string[i])) return 0,
                .NotWordBoundary => if (i == 0 and !isWord(string[i]) or isWord(string[i - 1]) == isWord(string[i])) return 0,
            }
            return null;
        },
        .Special => |s| {
            switch (s) {
                .Newline => if (string[i] == '\n') return 1,
                .CarriageReturn => if (string[i] == '\r') return 1,
                .Tab => if (string[i] == '\t') return 1,
                .VerticalTab => if (string[i] == 11) return 1,
                .FormFeed => if (string[i] == 12) return 1,
            }
            return null;
        },
        .Group => |g| {
            _ = g;
            @panic("group not yet implemented");
        },
    }
    return null;
}

fn isWord(character: u8) bool {
    return std.ascii.isAlphanumeric(character) or character == '_';
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

test "matches word boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\abc\> def\>
    );
    try std.testing.expect(regex.matches(
        \\abc def
    ));
    try std.testing.expect(!regex.matches(
        \\abcdef
    ));
}

test "matches start of line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\^abc\n^def
    );
    try std.testing.expect(regex.matches(
        \\abc
        \\def
    ));
    try std.testing.expect(!regex.matches(
        \\abc
        \\abc
    ));
}

test "matches question mark" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a?
    );
    try std.testing.expect(regex.matches(""));
    try std.testing.expect(regex.matches("a"));
    try std.testing.expect(!regex.matches("aa"));
}

test "matches plus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a+
    );
    try std.testing.expect(regex.matches("a"));
    try std.testing.expect(regex.matches("aa"));
    try std.testing.expect(regex.matches("aaa"));
    try std.testing.expect(!regex.matches("b"));
}

test "matches star" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a*
    );
    try std.testing.expect(regex.matches(""));
    try std.testing.expect(regex.matches("a"));
    try std.testing.expect(regex.matches("aa"));
    try std.testing.expect(regex.matches("aaa"));
    try std.testing.expect(!regex.matches("b"));
}

test "matches exact quantifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a{3}b
    );
    try std.testing.expect(!regex.matches("aa"));
    try std.testing.expect(regex.matches("aaab"));
    try std.testing.expect(!regex.matches("aaaa"));
}

test "debug" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a*
    );
    try std.testing.expect(!regex.matches("b"));
}
