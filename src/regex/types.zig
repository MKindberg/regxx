const std = @import("std");
const Regex = @import("regex.zig").Regex;

pub const RegexError = error{
    InvalidPattern,
};

pub const Token = struct {
    token: TokenType,
    text: []const u8,

    pub fn init(token: TokenType, text: []const u8) Token {
        return Token{ .token = token, .text = text };
    }

    pub fn newLiteral(last: ?Token, pattern: []const u8, idx: usize) Token {
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

pub const TokenType = union(enum) {
    Literal: []const u8,
    Any: void,
    CharacterGroup: CharacterGroupData,
    NegCharacterGroup: CharacterGroupData,
    CharacterClass: ClassData,
    Quantifier: QuantifierData,
    Anchor: AnchorData,
    Special: SpecialData,
    Group: GroupData,
};

pub const ClassData = enum {
    Control,
    Digit,
    NotDigit,
    Space,
    NotSpace,
    Word,
    NotWord,
    HexDigit,
    Octal,

    pub fn init(char: u8) ?ClassData {
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
    pub fn toString(self: ClassData) []const u8 {
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

pub const AnchorData = enum {
    Start,
    End,
    StartOfLine,
    EndOfLine,
    StartOfWord,
    EndOfWord,
    WordBoundary,
    NotWordBoundary,

    pub fn init(char: u8) ?AnchorData {
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

    pub fn toString(self: AnchorData) []const u8 {
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
pub const SpecialData = enum {
    Newline,
    CarriageReturn,
    Tab,
    VerticalTab,
    FormFeed,

    pub fn init(char: u8) ?SpecialData {
        return switch (char) {
            'n' => .Newline,
            'r' => .CarriageReturn,
            't' => .Tab,
            'v' => .VerticalTab,
            'f' => .FormFeed,
            else => null,
        };
    }

    pub fn toString(self: SpecialData) []const u8 {
        return switch (self) {
            .Newline => "newline",
            .CarriageReturn => "carriage return",
            .Tab => "tab",
            .VerticalTab => "vertical tab",
            .FormFeed => "form feed",
        };
    }
};
pub const GroupData = struct {
    groups: std.ArrayList(Regex),
    capture: bool,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !GroupData {
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

pub const CharacterGroupData = struct {
    characters: std.ArrayList(u8),
    ranges: std.ArrayList(Range),

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8) !CharacterGroupData {
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
        pub fn init(start: u8, end: u8) Range {
            return Range{ .start = start, .end = end };
        }
    };
};

pub const QuantifierData = struct {
    min: usize,
    max: usize,
    token: *Token,

    pub fn init(allocator: std.mem.Allocator, min: usize, max: usize, token: Token) !QuantifierData {
        const t = try allocator.create(Token);
        t.* = token;
        return QuantifierData{ .min = min, .max = max, .token = t };
    }
};
