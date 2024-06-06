const std = @import("std");

pub const Regex = struct {
    tokens: std.ArrayList(Token),

    const Self = @This();
    const Token = struct {
        token: TokenType,
        text: []const u8,

        fn init(token: TokenType, text: []const u8) Token {
            return Token{ .token = token, .text = text };
        }

        fn deinit(self: Token, allocator: std.mem.Allocator) void {
            self.token.deinit(allocator);
        }
    };
    const TokenType = union(enum) {
        Literal: u8,
        Any: void,
        CharacterGroup: []const u8,
        NegCharacterGroup: []const u8,
        CharacterClass: ClassData,
        Quantifier: QuantifierData,
        Anchor: AnchorData,

        fn deinit(self: TokenType, allocator: std.mem.Allocator) void {
            if (self == .Quantifier) {
                self.Quantifier.deinit(allocator);
            }
        }
        const ClassData = enum {
            Control,
            Digit,
            NotDigit,
            Space,
            NotSpace,
            Word,
            NotWord,
            HexDigit,
            Octal,

            fn init(char: u8) ?ClassData {
                return switch (char) {
                    'c' => .Control,
                    'd' => .Digit,
                    'D' => .NotDigit,
                    's' => .Space,
                    'S' => .NotSpace,
                    'w' => .Word,
                    'W' => .NotWord,
                    'h' => .HexDigit,
                    'o' => .Octal,
                    else => null,
                };
            }
            fn toString(self: ClassData) []const u8 {
                return switch (self) {
                    .Control => "control characters",
                    .Digit => "decimal digits [[0-9]]",
                    .NotDigit => "non-digit characters [[^0-9]]",
                    .Space => "whitespace characters [[ \\t\\n\\r\\f\\v]]",
                    .NotSpace => "non-whitespace characters [[^ \\t\\n\\r\\f\\v]]",
                    .Word => "word characters [[A-Za-z0-9_]]",
                    .NotWord => "non-word characters [[^A-Za-z0-9_]]",
                    .HexDigit => "hexadecimal digits [[0-9a-fA-F]]",
                    .Octal => "octal digits [[0-7]]",
                };
            }
        };

        const AnchorData = enum {
            Start,
            End,
            StartOfLine,
            EndOfLine,
            StartOfWord,
            EndOfWord,
            WordBoundary,
            NotWordBoundary,

            fn init(char: u8) ?AnchorData {
                return switch (char) {
                    '<' => .StartOfWord,
                    '>' => .EndOfWord,
                    'b' => .WordBoundary,
                    'B' => .NotWordBoundary,
                    'A' => .Start,
                    'Z' => .End,
                    else => null,
                };
            }

            fn toString(self: AnchorData) []const u8 {
                return switch (self) {
                    .Start => "start of the input",
                    .End => "end of the input",
                    .StartOfLine => "start of a line or the input",
                    .EndOfLine => "end of a line or the input",
                    .StartOfWord => "start of a word",
                    .EndOfWord => "end of a word",
                    .WordBoundary => "word boundary",
                    .NotWordBoundary => "not a word boundary",
                };
            }
        };
    };

    const QuantifierData = struct {
        min: usize,
        max: usize,
        token: *Token,

        fn init(allocator: std.mem.Allocator, min: usize, max: usize, token: Token) !QuantifierData {
            const t = try allocator.create(Token);
            t.* = token;
            return QuantifierData{ .min = min, .max = max, .token = t };
        }

        fn deinit(self: QuantifierData, allocator: std.mem.Allocator) void {
            self.token.deinit(allocator);
            allocator.destroy(self.token);
        }
    };

    const RegexError = error{
        InvalidPattern,
    };

    pub fn deinit(self: Self) void {
        for (self.tokens.items) |token| {
            token.deinit(self.tokens.allocator);
        }
        self.tokens.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) RegexError!Self {
        var tokens = std.ArrayList(Token).init(allocator);
        errdefer tokens.deinit();
        var i: usize = 0;
        while (i < pattern.len) : (i += 1) {
            const char = pattern[i .. i + 1];
            switch (pattern[i]) {
                '\\' => {
                    i += 1;
                    if (i == pattern.len) return RegexError.InvalidPattern;
                    const text = pattern[i - 1 .. i + 1];
                    const escaped_characters = "\\^$.|?*+()[]{}";
                    if (TokenType.ClassData.init(pattern[i])) |c| {
                        tokens.append(Token.init(.{ .CharacterClass = c }, text)) catch unreachable;
                    } else if (TokenType.AnchorData.init(pattern[i])) |a| {
                        tokens.append(Token.init(.{ .Anchor = a }, text)) catch unreachable;
                    } else if (std.mem.indexOfScalar(u8, escaped_characters, pattern[i]) != null) {
                        tokens.append(Token.init(.{ .Literal = pattern[i] }, text)) catch unreachable;
                    } else {
                        return RegexError.InvalidPattern;
                    }
                },
                '.' => _ = tokens.append(Token.init(.Any, char)) catch unreachable,
                '^' => _ = {
                    if (i == 0) tokens.append(Token.init(.{ .Anchor = .Start }, char)) catch unreachable else tokens.append(Token.init(.{ .Literal = pattern[i] }, char)) catch unreachable;
                },
                '$' => _ = {
                    if (i == pattern.len - 1) tokens.append(Token.init(.{ .Anchor = .End }, char)) catch unreachable else tokens.append(Token.init(.{ .Literal = pattern[i] }, char)) catch unreachable;
                },
                '[' => {
                    if (std.mem.indexOfScalar(u8, pattern[i..], ']')) |end| {
                        // TODO: handle ] in character group
                        if (pattern[i + 1] == '^') {
                            _ = tokens.append(Token.init(.{ .NegCharacterGroup = pattern[i + 2 .. i + end] }, pattern[i .. i + end + 1])) catch unreachable;
                        } else {
                            _ = tokens.append(Token.init(.{ .CharacterGroup = pattern[i + 1 .. i + end] }, pattern[i .. i + end + 1])) catch unreachable;
                        }
                        i += end;
                    } else return RegexError.InvalidPattern;
                },
                '*', '?', '+' => {
                    if (tokens.items.len == 0) return RegexError.InvalidPattern;
                    const last = tokens.pop();
                    if (last.token == .Anchor or last.token == .Quantifier) return RegexError.InvalidPattern;
                    const quantifier: QuantifierData = switch (pattern[i]) {
                        '*' => QuantifierData.init(allocator, 0, std.math.maxInt(usize), last) catch unreachable,
                        '?' => QuantifierData.init(allocator, 0, 1, last) catch unreachable,
                        '+' => QuantifierData.init(allocator, 1, std.math.maxInt(usize), last) catch unreachable,
                        else => unreachable,
                    };
                    tokens.append(Token.init(.{ .Quantifier = quantifier }, char)) catch unreachable;
                },
                '{' => {
                    if (tokens.items.len == 0) return RegexError.InvalidPattern;
                    const last = tokens.pop();
                    if (last.token == .Anchor or last.token == .Quantifier) return RegexError.InvalidPattern;
                    const start = i;
                    const end = start + (std.mem.indexOfScalar(u8, pattern[i..], '}') orelse return RegexError.InvalidPattern);
                    if (std.mem.indexOfScalar(u8, pattern[start..end], ',')) |m| {
                        const mid = m + i;
                        const min = std.fmt.parseInt(usize, pattern[start + 1 .. mid], 10) catch return RegexError.InvalidPattern;
                        const max = if (mid + 1 == end) std.math.maxInt(usize) else std.fmt.parseInt(usize, pattern[mid + 1 .. end], 10) catch return RegexError.InvalidPattern;
                        tokens.append(Token.init(.{ .Quantifier = QuantifierData.init(allocator, min, max, last) catch unreachable }, pattern[start .. end + 1])) catch unreachable;
                    } else {
                        const n = std.fmt.parseInt(usize, pattern[start + 1 .. end], 10) catch return RegexError.InvalidPattern;
                        tokens.append(Token.init(.{ .Quantifier = QuantifierData.init(allocator, n, n, last) catch unreachable }, pattern[start .. end + 1])) catch unreachable;
                    }
                    i = end;
                },
                else => _ = tokens.append(Token.init(.{ .Literal = pattern[i] }, char)) catch unreachable,
            }
        }
        return Self{ .tokens = tokens };
    }

    pub fn print(self: Self, writer: anytype) !void {
        try print2(writer, self.tokens.items, 0);
    }

    fn print2(writer: anytype, tokens: []const Token, indent: usize) !void {
        for (tokens) |tok| {
            for (0..indent) |_| {
                try writer.print("    ", .{});
            }
            switch (tok.token) {
                .Literal => |l| {
                    try writer.print("{s} matches {c} litteraly\n", .{ tok.text, l });
                },
                .Any => {
                    try writer.print("{s} matches any character\n", .{
                        tok.text,
                    });
                },
                .CharacterGroup => |g| {
                    try writer.print("[{s}] matches any character in the group {s}\n", .{ tok.text, g });
                },
                .NegCharacterGroup => |g| {
                    try writer.print("[{s}] matches any character not in the group {s}\n", .{ tok.text, g });
                },
                .CharacterClass => |c| {
                    try writer.print("{s} matches {s}\n", .{ tok.text, c.toString() });
                },
                .Quantifier => |q| {
                    const arr = [1]Token{q.token.*};
                    try print2(writer, arr[0..], indent);
                    if (q.max == std.math.maxInt(usize)) {
                        try writer.print("    Matches the previous token between {d} and unlimited times\n", .{q.min});
                    } else if (q.min == q.max) {
                        try writer.print("    Matches the previous token exactly {d} times\n", .{q.min});
                    } else {
                        try writer.print("    Matches the previous token between {d} and {d} times\n", .{ q.min, q.max });
                    }
                },
                .Anchor => |a| {
                    try writer.print("{s} matches {s}\n", .{ tok.text, a.toString() });
                },
            }
        }
    }
};
