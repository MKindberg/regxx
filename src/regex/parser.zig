const std = @import("std");
const Token = @import("types.zig").Token;
const RegexError = @import("types.zig").RegexError;
const TokenType = @import("types.zig").TokenType;
const QuantifierData = @import("types.zig").QuantifierData;
const types = @import("types.zig");
const Regex = @import("regex.zig").Regex;

pub fn parse(allocator: std.mem.Allocator, pattern: []const u8) RegexError!Regex {
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
                if (types.ClassData.init(pattern[i])) |c| {
                    tokens.append(Token.init(.{ .CharacterClass = c }, text)) catch unreachable;
                } else if (types.AnchorData.init(pattern[i])) |a| {
                    tokens.append(Token.init(.{ .Anchor = a }, text)) catch unreachable;
                } else if (types.SpecialData.init(pattern[i])) |s| {
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
                        _ = tokens.append(Token.init(.{ .NegCharacterGroup = try types.CharacterGroupData.init(allocator, pattern[i + 2 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
                    } else {
                        _ = tokens.append(Token.init(.{ .CharacterGroup = try types.CharacterGroupData.init(allocator, pattern[i + 2 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
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
                    _ = tokens.append(Token.init(.{ .Group = try types.GroupData.init(allocator, pattern[i + 1 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
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
    return Regex{ .tokens = tokens };
}
