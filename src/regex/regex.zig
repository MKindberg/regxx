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

        fn newLiteral(last: ?Token, pattern: []const u8, idx: usize) Token {
            if (last == null or last.?.token != .Literal) {
                const char = pattern[idx .. idx + 1];
                return Token.init(.{ .Literal = char }, char);
            }
            const start = idx - last.?.token.Literal.len;
            const end = idx + 1;
            const text = pattern[start..end];
            return Token.init(.{ .Literal = text }, text);
        }
    };
    const TokenType = union(enum) {
        Literal: []const u8,
        Any: void,
        CharacterGroup: CharacterGroupData,
        NegCharacterGroup: CharacterGroupData,
        CharacterClass: ClassData,
        Quantifier: QuantifierData,
        Anchor: AnchorData,
        Special: SpecialData,
        Group: GroupData,

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

        const SpecialData = enum {
            Newline,
            CarriageReturn,
            Tab,
            VerticalTab,
            FormFeed,

            fn init(char: u8) ?SpecialData {
                return switch (char) {
                    'n' => .Newline,
                    'r' => .CarriageReturn,
                    't' => .Tab,
                    'v' => .VerticalTab,
                    'f' => .FormFeed,
                    else => null,
                };
            }

            fn toString(self: SpecialData) []const u8 {
                return switch (self) {
                    .Newline => "newline",
                    .CarriageReturn => "carriage return",
                    .Tab => "tab",
                    .VerticalTab => "vertical tab",
                    .FormFeed => "form feed",
                };
            }
        };

        const GroupData = struct {
            groups: std.ArrayList(Regex),
            capture: bool,

            fn init(allocator: std.mem.Allocator, pattern: []const u8) !GroupData {
                var groups = std.ArrayList(Regex).init(allocator);
                const pat = if (std.mem.startsWith(u8, pattern, "?:")) pattern[2..] else pattern;
                var it = std.mem.splitScalar(u8, pat, '|');
                while (it.next()) |p| {
                    const r = try Regex.initLeaky(allocator, p);
                    groups.append(r) catch unreachable;
                }
                return GroupData{ .groups = groups, .capture = !std.mem.startsWith(u8, pattern, "?:") };
            }
        };

        const CharacterGroupData = struct {
            characters: std.ArrayList(u8),
            ranges: std.ArrayList(Range),

            fn init(allocator: std.mem.Allocator, pattern: []const u8) !CharacterGroupData {
                var self = CharacterGroupData{
                    .characters = std.ArrayList(u8).init(allocator),
                    .ranges = std.ArrayList(Range).init(allocator),
                };

                var i: usize = 0;
                while (i < pattern.len) : (i += 1) {
                    if (i > 0 and i < pattern.len - 1 and pattern[i + 1] == '-') {
                        if (pattern[i] > pattern[i + 2]) return RegexError.InvalidPattern;
                        self.ranges.append(Range.init(pattern[i], pattern[i + 2])) catch unreachable;
                        i += 2;
                    } else if (std.mem.indexOfScalar(u8, self.characters.items, pattern[i]) == null) self.characters.append(pattern[i]) catch unreachable;
                }

                return self;
            }

            const Range = struct {
                start: u8,
                end: u8,
                fn init(start: u8, end: u8) Range {
                    return Range{ .start = start, .end = end };
                }
            };
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
    };

    const RegexError = error{
        InvalidPattern,
    };

    pub fn initLeaky(allocator: std.mem.Allocator, pattern: []const u8) RegexError!Self {
        var tokens = std.ArrayList(Token).init(allocator);
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
                    } else if (TokenType.SpecialData.init(pattern[i])) |s| {
                        tokens.append(Token.init(.{ .Special = s }, text)) catch unreachable;
                    } else if (std.mem.indexOfScalar(u8, escaped_characters, pattern[i]) != null) {
                        var prev = tokens.popOrNull();
                        if (prev != null and prev.?.token != .Literal) {
                            tokens.append(prev.?) catch unreachable;
                            prev = null;
                        }
                        tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
                    } else {
                        return RegexError.InvalidPattern;
                    }
                },
                '.' => _ = tokens.append(Token.init(.Any, char)) catch unreachable,
                '^' => _ = {
                    if (i == 0) {
                        tokens.append(Token.init(.{ .Anchor = .Start }, char)) catch unreachable;
                    } else {
                        var prev = tokens.popOrNull();
                        if (prev != null and prev.?.token != .Literal) {
                            tokens.append(prev.?) catch unreachable;
                            prev = null;
                        }
                        tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
                    }
                },
                '$' => _ = {
                    if (i == pattern.len - 1) {
                        tokens.append(Token.init(.{ .Anchor = .End }, char)) catch unreachable;
                    } else {
                        var prev = tokens.popOrNull();
                        if (prev != null and prev.?.token != .Literal) {
                            tokens.append(prev.?) catch unreachable;
                            prev = null;
                        }
                        tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
                    }
                },
                '[' => {
                    if (std.mem.indexOfScalar(u8, pattern[i..], ']')) |end| {
                        // TODO: handle ] in character group
                        if (pattern[i + 1] == '^') {
                            _ = tokens.append(Token.init(.{ .NegCharacterGroup = try TokenType.CharacterGroupData.init(allocator, pattern[i + 2 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
                        } else {
                            _ = tokens.append(Token.init(.{ .CharacterGroup = try TokenType.CharacterGroupData.init(allocator, pattern[i + 2 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
                        }
                        i += end;
                    } else return RegexError.InvalidPattern;
                },
                '*', '?', '+' => {
                    if (tokens.items.len == 0) return RegexError.InvalidPattern;
                    var last = tokens.pop();
                    if (last.token == .Anchor or last.token == .Quantifier) return RegexError.InvalidPattern;
                    last = if (last.token == .Literal and last.text.len > 1) last: {
                        const text = last.text;
                        tokens.append(Token.init(.{ .Literal = text[0 .. text.len - 1] }, text[0 .. text.len - 1])) catch unreachable;
                        break :last Token.init(.{ .Literal = text[text.len - 1 ..] }, text[text.len - 1 ..]);
                    } else last;
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
                    var last = tokens.pop();
                    if (last.token == .Anchor or last.token == .Quantifier) return RegexError.InvalidPattern;
                    last = if (last.token == .Literal and last.text.len > 1) last: {
                        const text = last.text;
                        tokens.append(Token.init(.{ .Literal = text[0 .. text.len - 1] }, text[0 .. text.len - 1])) catch unreachable;
                        break :last Token.init(.{ .Literal = text[text.len - 1 ..] }, text[text.len - 1 ..]);
                    } else last;
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
                '(' => {
                    if (std.mem.indexOfScalar(u8, pattern[i..], ')')) |end| {
                        _ = tokens.append(Token.init(.{ .Group = try TokenType.GroupData.init(allocator, pattern[i + 1 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
                        i += end;
                    } else return RegexError.InvalidPattern;
                },
                else => {
                    var prev = tokens.popOrNull();
                    if (prev != null and prev.?.token != .Literal) {
                        tokens.append(prev.?) catch unreachable;
                        prev = null;
                    }
                    tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
                },
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
                    try writer.print("{s} matches {s} litteraly\n", .{ tok.text, l });
                },
                .Any => {
                    try writer.print("{s} matches any character\n", .{
                        tok.text,
                    });
                },
                .CharacterGroup => |g| {
                    try writer.print("[{s}] matches any character ", .{tok.text});
                    if (g.characters.items.len > 0) {
                        try writer.print("in the group {s}", .{g.characters.items});
                        if (g.ranges.items.len > 0) try writer.print(" or ", .{});
                    }
                    if (g.ranges.items.len > 0) {
                        for (g.ranges.items[0 .. g.ranges.items.len - 1]) |r| {
                            try writer.print("between {c} and {c} or ", .{ r.start, r.end });
                        }
                        try writer.print("between {c} and {c}", .{ g.ranges.getLast().start, g.ranges.getLast().end });
                    }
                    try writer.print("\n", .{});
                },
                .NegCharacterGroup => |g| {
                    try writer.print("[{s}] matches any character not ", .{tok.text});
                    if (g.characters.items.len > 0) {
                        try writer.print("in the group {s}", .{g.characters.items});
                        if (g.ranges.items.len > 0) try writer.print(" or ", .{});
                    }
                    if (g.ranges.items.len > 0) {
                        for (g.ranges.items[0 .. g.ranges.items.len - 1]) |r| {
                            try writer.print("between {c} and {c} or ", .{ r.start, r.end });
                        }
                        try writer.print("between {c} and {c}", .{ g.ranges.getLast().start, g.ranges.getLast().end });
                    }
                    try writer.print("\n", .{});
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
                .Special => |s| {
                    try writer.print("{s} matches a {s}\n", .{ tok.text, s.toString() });
                },
                .Group => |group| {
                    if (group.groups.items.len == 0) {
                        try writer.print("{s} matches the following {s} group:\n", .{ tok.text, if (group.capture) "capturing" else "non-capturing" });
                        try print2(writer, group.groups.items[0].tokens.items, indent + 1);
                    } else {
                        try writer.print("{s} matches one of the following groups:\n", .{tok.text});
                        for (group.groups.items) |g| {
                            try print2(writer, g.tokens.items, indent + 1);
                            try writer.print("\n", .{});
                        }
                    }
                },
            }
        }
    }
};
