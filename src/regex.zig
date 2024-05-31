const std = @import("std");

pub const Regex = struct {
    const Token = union(enum) {
        Literal: u8,
        Any: void,
        CharacterGroup: []const u8,
        NegCharacterGroup: []const u8,
        CharacterClass: u8,
        Quantifier: QuantifierData,
        Start: void,
        End: void,
    };

    const QuantifierData = struct {
        min: usize,
        max: usize,
    };

    const RegexError = error{
        InvalidPattern,
    };

    pub fn parse(allocator: std.mem.Allocator, pattern: []const u8) RegexError!std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(allocator);
        errdefer tokens.deinit();
        var i: usize = 0;
        while (i < pattern.len) : (i += 1) {
            switch (pattern[i]) {
                '\\' => {
                    i += 1;
                    if (i == pattern.len) return RegexError.InvalidPattern;
                    const character_classes = "cdDsSwWxO";
                    const escaped_characters = "\\^$.|?*+()[]{}";
                    if (std.mem.indexOfScalar(u8, character_classes, pattern[i]) != null) {
                        _ = tokens.append(Token{ .CharacterClass = pattern[i] }) catch unreachable;
                    } else if (std.mem.indexOfScalar(u8, escaped_characters, pattern[i]) != null) {
                        _ = tokens.append(Token{ .Literal = pattern[i] }) catch unreachable;
                    } else {
                        return RegexError.InvalidPattern;
                    }
                },
                '.' => _ = tokens.append(Token.Any) catch unreachable,
                '^' => _ = {
                    if (i == 0) tokens.append(Token.Start) catch unreachable else tokens.append(Token{ .Literal = pattern[i] }) catch unreachable;
                },
                '$' => _ = {
                    if (i == pattern.len - 1) tokens.append(Token.End) catch unreachable else tokens.append(Token{ .Literal = pattern[i] }) catch unreachable;
                },
                '[' => {
                    if (std.mem.indexOfScalar(u8, pattern[i..], ']')) |end| {
                        if (pattern[i + 1] == '^') {
                            _ = tokens.append(Token{ .NegCharacterGroup = pattern[i + 2 .. i + end] }) catch unreachable;
                        } else {
                            _ = tokens.append(Token{ .CharacterGroup = pattern[i + 1 .. i + end] }) catch unreachable;
                        }
                        i += end;
                    } else return RegexError.InvalidPattern;
                },
                '*', '?', '+' => {
                    if (tokens.items.len == 0) return RegexError.InvalidPattern;
                    const last = tokens.getLast();
                    if (last == .Start or last == .End or last == .Quantifier) return RegexError.InvalidPattern;
                    const quantifier: QuantifierData = switch (pattern[i]) {
                        '*' => .{ .min = 0, .max = std.math.maxInt(usize) },
                        '?' => .{ .min = 0, .max = 1 },
                        '+' => .{ .min = 1, .max = std.math.maxInt(usize) },
                        else => unreachable,
                    };
                    tokens.insert(tokens.items.len - 1, Token{ .Quantifier = quantifier }) catch unreachable;
                },
                '{' => {
                    if (tokens.items.len == 0) return RegexError.InvalidPattern;
                    const last = tokens.getLast();
                    if (last == .Start or last == .End or last == .Quantifier) return RegexError.InvalidPattern;
                    const start = i;
                    const end = start + (std.mem.indexOfScalar(u8, pattern[i..], '}') orelse return RegexError.InvalidPattern);
                    if (std.mem.indexOfScalar(u8, pattern[i..], ',')) |m| {
                        const mid = m + i;
                        const min = std.fmt.parseInt(usize, pattern[start + 1 .. mid], 10) catch return RegexError.InvalidPattern;
                        const max = if (mid + 1 == end) std.math.maxInt(usize) else std.fmt.parseInt(usize, pattern[mid + 1 .. end], 10) catch return RegexError.InvalidPattern;
                        tokens.insert(tokens.items.len - 1, Token{ .Quantifier = .{ .min = min, .max = max } }) catch unreachable;
                    } else {
                        const n = std.fmt.parseInt(usize, pattern[start + 1 .. end], 10) catch return RegexError.InvalidPattern;
                        tokens.insert(tokens.items.len - 1, Token{ .Quantifier = .{ .min = n, .max = n } }) catch unreachable;
                    }
                    i = end;
                },
                else => _ = tokens.append(Token{ .Literal = pattern[i] }) catch unreachable,
            }
        }
        return tokens;
    }


};
