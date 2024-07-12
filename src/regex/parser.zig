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
                try parseEscape(&tokens, pattern, i);
            },
            '.' => _ = tokens.append(Token.init(.Any, char)) catch unreachable,
            '^' => _ = parseCarret(&tokens, pattern, i),
            '$' => _ = parseDollar(&tokens, pattern, i),
            '[' => i += try parseBracket(allocator, &tokens, pattern, i),
            '*', '?', '+' => try parseQuantifier(allocator, &tokens, pattern, i),
            '{' => i = try parseBrace(allocator, &tokens, pattern, i),
            '(' => i += try parseParen(allocator, &tokens, pattern, i),
            else => parseOther(&tokens, pattern, i),
        }
    }
    return Regex{ .tokens = tokens };
}

fn parseEscape(tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) !void {
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
}

fn parseCarret(tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) void {
    if (i == 0) {
        tokens.append(Token.init(.{ .Anchor = .Start }, pattern[0..1])) catch unreachable;
    } else {
        var prev = tokens.popOrNull();
        if (prev != null and prev.?.token != .Literal) {
            tokens.append(prev.?) catch unreachable;
            prev = null;
        }
        tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
    }
}

fn parseDollar(tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) void {
    if (i == pattern.len - 1) {
        tokens.append(Token.init(.{ .Anchor = .End }, pattern[i .. i + 1])) catch unreachable;
    } else {
        var prev = tokens.popOrNull();
        if (prev != null and prev.?.token != .Literal) {
            tokens.append(prev.?) catch unreachable;
            prev = null;
        }
        tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
    }
}

fn parseBracket(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) !usize {
    if (std.mem.indexOfScalar(u8, pattern[i..], ']')) |end| {
        // TODO: handle ] in character group
        if (pattern[i + 1] == '^') {
            _ = tokens.append(Token.init(.{ .NegCharacterGroup = try types.CharacterGroupData.init(allocator, pattern[i + 2 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
        } else {
            _ = tokens.append(Token.init(.{ .CharacterGroup = try types.CharacterGroupData.init(allocator, pattern[i + 1 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
        }
        return end;
    }
    return RegexError.InvalidPattern;
}
fn parseQuantifier(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) !void {
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
    tokens.append(Token.init(.{ .Quantifier = quantifier }, pattern[i .. i + 1])) catch unreachable;
}

fn parseBrace(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) !usize {
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
    return end;
}

fn parseParen(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) !usize {
    if (std.mem.indexOfScalar(u8, pattern[i..], ')')) |end| {
        _ = tokens.append(Token.init(.{ .Group = try types.GroupData.init(allocator, pattern[i + 1 .. i + end]) }, pattern[i .. i + end + 1])) catch unreachable;
        return end;
    }
    return RegexError.InvalidPattern;
}

fn parseOther(tokens: *std.ArrayList(Token), pattern: []const u8, i: usize) void {
    var prev = tokens.popOrNull();
    if (prev != null and prev.?.token != .Literal) {
        tokens.append(prev.?) catch unreachable;
        prev = null;
    }
    tokens.append(Token.newLiteral(prev, pattern, i)) catch unreachable;
}

test "parseLiteral" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "abc";
    const regex = try parse(allocator, pattern);

    try std.testing.expectEqual(1, regex.tokens.items.len);
    try std.testing.expectEqual(TokenType{ .Literal = pattern }, regex.tokens.items[0].token);
}

test "parseAny" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = ".";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(1, regex.tokens.items.len);
    try std.testing.expectEqual(.Any, regex.tokens.items[0].token);
}

test "parseCarret" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "^abc^";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(2, regex.tokens.items.len);
    try std.testing.expectEqual(TokenType{ .Anchor = .Start }, regex.tokens.items[0].token);
    try std.testing.expectEqualStrings("abc^", regex.tokens.items[1].token.Literal);
}

test "parseDollar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "a$bc$";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(2, regex.tokens.items.len);
    try std.testing.expectEqualStrings("a$bc", regex.tokens.items[0].token.Literal);
    try std.testing.expectEqual(TokenType{ .Anchor = .End }, regex.tokens.items[1].token);
}

test "CharacterGroupDuplicate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "[abca]";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(1, regex.tokens.items.len);
    try std.testing.expectEqualStrings("abc", regex.tokens.items[0].token.CharacterGroup.characters.items);
}

test "CharacterGroupNeg" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "[^ab]";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(1, regex.tokens.items.len);
    try std.testing.expectEqualStrings("ab", regex.tokens.items[0].token.NegCharacterGroup.characters.items);
}

test "CharacterGroupRange" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "[a-z]";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(1, regex.tokens.items.len);
    try std.testing.expectEqual(0, regex.tokens.items[0].token.CharacterGroup.characters.items.len);
    try std.testing.expectEqual(1, regex.tokens.items[0].token.CharacterGroup.ranges.items.len);
    try std.testing.expectEqual('a', regex.tokens.items[0].token.CharacterGroup.ranges.items[0].start);
    try std.testing.expectEqual('z', regex.tokens.items[0].token.CharacterGroup.ranges.items[0].end);
}

test "CharacterGroup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();
    const pattern = "[aba-z]";
    const regex = try parse(allocator, pattern);
    try std.testing.expectEqual(1, regex.tokens.items.len);
    try std.testing.expectEqual(2, regex.tokens.items[0].token.CharacterGroup.characters.items.len);
    try std.testing.expectEqualStrings("ab", regex.tokens.items[0].token.CharacterGroup.characters.items);
    try std.testing.expectEqual(1, regex.tokens.items[0].token.CharacterGroup.ranges.items.len);
    try std.testing.expectEqual('a', regex.tokens.items[0].token.CharacterGroup.ranges.items[0].start);
    try std.testing.expectEqual('z', regex.tokens.items[0].token.CharacterGroup.ranges.items[0].end);
}
