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
        CharacterClass: u8,
        Quantifier: QuantifierData,
        Start: void,
        End: void,

        fn deinit(self: TokenType, allocator: std.mem.Allocator) void {
            if (self == .Quantifier) {
                self.Quantifier.deinit(allocator);
            }
        }
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
                    const character_classes = "cdDsSwWxO";
                    const escaped_characters = "\\^$.|?*+()[]{}";
                    if (std.mem.indexOfScalar(u8, character_classes, pattern[i]) != null) {
                        tokens.append(Token.init(.{ .CharacterClass = pattern[i] }, text)) catch unreachable;
                    } else if (std.mem.indexOfScalar(u8, escaped_characters, pattern[i]) != null) {
                        tokens.append(Token.init(.{ .Literal = pattern[i] }, text)) catch unreachable;
                    } else {
                        return RegexError.InvalidPattern;
                    }
                },
                '.' => _ = tokens.append(Token.init(.Any, char)) catch unreachable,
                '^' => _ = {
                    if (i == 0) tokens.append(Token.init(.Start, char)) catch unreachable else tokens.append(Token.init(.{ .Literal = pattern[i] }, char)) catch unreachable;
                },
                '$' => _ = {
                    if (i == pattern.len - 1) tokens.append(Token.init(.End, char)) catch unreachable else tokens.append(Token.init(.{ .Literal = pattern[i] }, char)) catch unreachable;
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
                    if (last.token == .Start or last.token == .End or last.token == .Quantifier) return RegexError.InvalidPattern;
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
                    if (last.token == .Start or last.token == .End or last.token == .Quantifier) return RegexError.InvalidPattern;
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
        try printPattern(writer, self.tokens.items, 0);
    }

    fn printPattern(writer: anytype, tokens: []Token, indent: usize) !void {
        if (tokens.len == 0) return;
        _ = indent;
        // The ArrayList will eat one pair of []
        try writer.print("{s}", .{tokens[0].text});
        std.log.info("TOK: {any}", .{tokens});
        try printPattern(writer, tokens[1..], 0);
        // var t = tokens;
        // for (0..indent) |_| try writer.print("    ", .{});
        // if (tokens.len == 0) return;
        // switch (tokens[0]) {
        //     .Literal => |l| {
        //         try writer.print("{c} matches {c} litteraly\n", .{ l, l });
        //     },
        //     .Any => {
        //         try writer.print("Matches any character", .{});
        //     },
        //     .CharacterGroup => |g| {
        //         try writer.print("[{s}] matches any character in the group {s}\n", .{ g, g });
        //     },
        //     .NegCharacterGroup => |g| {
        //         try writer.print("[^{s}] matches any character not in the group {s}\n", .{ g, g });
        //     },
        //     .CharacterClass => {},
        //     .Quantifier => {
        //         try writer.print("Matches the previous token (below) {d} to {d} times\n", .{ tokens[0].Quantifier.min, tokens[0].Quantifier.max });
        //         try printPattern(writer, tokens[1..2], indent + 1);
        //         t = tokens[1..];
        //     },
        //     .Start => {
        //         try writer.print("^ matches the start of a line\n", .{});
        //     },
        //     .End => {
        //         try writer.print("$ matches the end of a line\n", .{});
        //     },
        // }
        // try printPattern(writer, t[1..], indent);
    }
};
