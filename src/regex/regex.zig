const std = @import("std");
const Token = @import("types.zig").Token;
const RegexError = @import("types.zig").RegexError;
const TokenType = @import("types.zig").TokenType;
const QuantifierData = @import("types.zig").QuantifierData;
const types = @import("types.zig");
const parser = @import("parser.zig");
const printer = @import("printer.zig");
const matcher = @import("matcher.zig");

pub const Regex = struct {
    tokens: std.ArrayList(Token),

    const Self = @This();

    pub fn initLeaky(allocator: std.mem.Allocator, pattern: []const u8) RegexError!Self {
        return parser.parse(allocator, pattern);
    }

    pub fn print(self: Self, writer: anytype) !void {
        try printer.print(self, writer);
    }

    pub fn matches(self: Self, input: []const u8) bool {
        return matcher.matches(self, input);
    }

    pub fn matchesAll(self: Self, input: []const u8) bool {
        return matcher.matchesAll(self, input);
    }
};
