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
            'x' => .HexDigit,
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

        if (pattern.len == 0) return self;

        if (pattern[0] == ':') { // POSIX classes
            if (std.mem.eql(u8, pattern, "[:upper:]")) {
                self.ranges.append(Range.init('A', 'Z')) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":lower:")) {
                self.ranges.append(Range.init('a', 'z')) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":alpha:")) {
                self.ranges.append(Range.init('A', 'Z')) catch unreachable;
                self.ranges.append(Range.init('a', 'z')) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":alnum:")) {
                self.ranges.append(Range.init('A', 'Z')) catch unreachable;
                self.ranges.append(Range.init('a', 'z')) catch unreachable;
                self.ranges.append(Range.init('0', '9')) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":digit:")) {
                self.ranges.append(Range.init('0', '9')) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":xdigit:")) {
                self.ranges.append(Range.init('0', '9')) catch unreachable;
                self.ranges.append(Range.init('A', 'F')) catch unreachable;
                self.ranges.append(Range.init('a', 'f')) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":punct:")) {
                self.characters.appendSlice("!.,") catch unreachable; // Probably missing some
            } else if (std.mem.eql(u8, pattern, ":blank:")) {
                self.characters.append(' ') catch unreachable;
                self.characters.append('\t') catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":space:")) {
                self.characters.append(' ') catch unreachable;
                self.characters.append('\t') catch unreachable;
                self.characters.append('\n') catch unreachable;
                self.characters.append('\r') catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":cntrl:")) {
                self.ranges.append(Range.init(0, 31)) catch unreachable;
                self.characters.append(127) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":graph:")) {
                self.ranges.append(Range.init(33, 126)) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":print:")) {
                self.ranges.append(Range.init(32, 126)) catch unreachable;
            } else if (std.mem.eql(u8, pattern, ":word:")) {
                self.ranges.append(Range.init('A', 'Z')) catch unreachable;
                self.ranges.append(Range.init('a', 'z')) catch unreachable;
                self.ranges.append(Range.init('0', '9')) catch unreachable;
                self.characters.append('_') catch unreachable;
            }
            return self;
        }

        var i: usize = 0;
        while (i < pattern.len) : (i += 1) {
            if (i < pattern.len - 2 and pattern[i + 1] == '-') {
                if (pattern[i] > pattern[i + 2]) return RegexError.InvalidPattern;
                self.ranges.append(Range.init(pattern[i], pattern[i + 2])) catch unreachable;
                i += 2;
            } else if (std.mem.indexOfScalar(u8, self.characters.items, pattern[i]) == null) {
                if (i < pattern.len - 1 and pattern[i] == '\\' and pattern[i + 1] == ']') continue;
                self.characters.append(pattern[i]) catch unreachable;
            }
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

pub const Match = struct {
    start: usize = 0,
    end: usize,
    // captures: []const u8 = .{},
};
