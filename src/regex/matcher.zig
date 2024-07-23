const std = @import("std");
const types = @import("types.zig");
const Regex = @import("regex.zig").Regex;

pub fn matchesAll(self: Regex, string: []const u8) bool {
    if (matches(self, string)) |match| {
        return match.start == 0 and match.end == string.len;
    }
    return false;
}

pub fn matches(self: Regex, string: []const u8) ?types.Match {
    const tokens = self.tokens.items;
    if (tokens.len == 0) return null;
    return matchesRec(tokens, string, 0);
}

fn matchesRec(tokens: []const types.Token, string: []const u8, i: usize) ?types.Match {
    if (tokens.len == 0) return .{ .end = i };
    if (string.len == i and tokens.len == 1 and tokens[0].token == .Quantifier and tokens[0].token.Quantifier.min == 0) return .{ .end = i };
    if (tokens.len == 1 and tokens[0].token == .Anchor) {
        switch (tokens[0].token.Anchor) {
            .End => if (string.len == i) return .{ .end = i } else return null,
            .EndOfLine => if (string.len == i) return .{ .end = i },
            .EndOfWord, .WordBoundary => if (string.len == i and isWord(string[i - 1])) return .{ .end = i } else if (string.len == i) return null,
            .NotWordBoundary => if (i == 0 and !isWord(string[i]) or string.len == i and !isWord(string[i - 1])) return .{ .end = i },
            else => {},
        }
    }
    if (string.len <= i) return null;

    if (tokens[0].token == .Quantifier) {
        const q = tokens[0].token.Quantifier;

        var max: usize = 0;
        var j: usize = 0;
        while (max < q.max) : (max += 1) {
            if(i + j >= string.len) break;
            if (matchesTok(q.token.token, string, i + j)) |steps| {
                j += steps;
            } else break;
        }

        if (max < q.min) return null;

        while (max >= q.min) : (max -= 1) {
            j = 0;
            for (0..max) |_| {
                if (matchesTok(q.token.token, string, i + j)) |steps| {
                    j += steps;
                }
            }
            if (matchesRec(tokens[1..], string, i + j)) |m| {
                return m;
            }
            max -= 1;
        }
        return null;
    }

    if (matchesTok(tokens[0].token, string, i)) |steps| return matchesRec(tokens[1..], string, i + steps);
    return null;
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
            for (g.groups.items) |r| {
                if (matches(r, string[i..])) |m| {
                    return m.end;
                }
            }
            return null;
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
    try std.testing.expect(regex.matchesAll("abc"));
}

test "matches any" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "..");
    try std.testing.expect(regex.matchesAll("ab"));
    try std.testing.expect(regex.matchesAll("bc"));
    try std.testing.expect(regex.matchesAll("cd"));
}

test "matches character group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "[abce-h]");
    try std.testing.expect(regex.matchesAll("a"));
    try std.testing.expect(regex.matchesAll("b"));
    try std.testing.expect(regex.matchesAll("c"));
    try std.testing.expect(!regex.matchesAll("d"));
    try std.testing.expect(regex.matchesAll("e"));
    try std.testing.expect(regex.matchesAll("f"));
    try std.testing.expect(regex.matchesAll("g"));
    try std.testing.expect(regex.matchesAll("h"));
    try std.testing.expect(!regex.matchesAll("i"));
}

test "matches neg character group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(), "[^abce-h]");
    try std.testing.expect(!regex.matchesAll("a"));
    try std.testing.expect(!regex.matchesAll("b"));
    try std.testing.expect(!regex.matchesAll("c"));
    try std.testing.expect(regex.matchesAll("d"));
    try std.testing.expect(!regex.matchesAll("e"));
    try std.testing.expect(!regex.matchesAll("f"));
    try std.testing.expect(!regex.matchesAll("g"));
    try std.testing.expect(!regex.matchesAll("h"));
    try std.testing.expect(regex.matchesAll("i"));
}

test "matches character class" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\\d
    );
    try std.testing.expect(regex.matchesAll("2"));
    try std.testing.expect(regex.matchesAll("9"));
    try std.testing.expect(!regex.matchesAll("a"));

    const regex2 = try Regex.initLeaky(arena.allocator(),
        \\\x
    );
    try std.testing.expect(regex2.matchesAll("2"));
    try std.testing.expect(regex2.matchesAll("9"));
    try std.testing.expect(regex2.matchesAll("a"));
    try std.testing.expect(regex2.matchesAll("B"));
}

test "matches special" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a\nb
    );
    try std.testing.expect(regex.matchesAll(
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
    try std.testing.expect(regex.matchesAll(
        \\abc def
    ));
    try std.testing.expect(!regex.matchesAll(
        \\abcdef
    ));
}

test "matches start of line" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\^abc\n^def
    );
    try std.testing.expect(regex.matchesAll(
        \\abc
        \\def
    ));
    try std.testing.expect(!regex.matchesAll(
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
    try std.testing.expect(regex.matchesAll(""));
    try std.testing.expect(regex.matchesAll("a"));
    try std.testing.expect(!regex.matchesAll("aa"));
}

test "matches plus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a+$
    );
    try std.testing.expect(regex.matchesAll("a"));
    try std.testing.expect(regex.matchesAll("aa"));
    try std.testing.expect(regex.matchesAll("aaa"));
    try std.testing.expect(!regex.matchesAll("b"));
}

test "matches star" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a*
    );
    try std.testing.expect(regex.matchesAll(""));
    try std.testing.expect(regex.matchesAll("a"));
    try std.testing.expect(regex.matchesAll("aa"));
    try std.testing.expect(regex.matchesAll("aaa"));
    try std.testing.expect(!regex.matchesAll("b"));
}

test "matches exact quantifier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\a{3}b
    );
    try std.testing.expect(!regex.matchesAll("aa"));
    try std.testing.expect(regex.matchesAll("aaab"));
    try std.testing.expect(!regex.matchesAll("aaaa"));
}

test "group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\(a|b)+
    );
    try std.testing.expect(regex.matchesAll("ab"));
    try std.testing.expect(regex.matchesAll("b"));
    try std.testing.expect(!regex.matchesAll("c"));
}
test "group2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\(a\d|b)+
    );
    try std.testing.expect(regex.matchesAll("a2b"));
}

test "quantifier inside group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\(a+)a
    );
    try std.testing.expect(regex.matchesAll("aa"));
}

test "debug" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const regex = try Regex.initLeaky(arena.allocator(),
        \\debug
    );
    try std.testing.expect(regex.matchesAll("debug"));
}
