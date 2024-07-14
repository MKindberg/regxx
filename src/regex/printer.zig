const std = @import("std");

const Regex = @import("regex.zig").Regex;
const Token = @import("types.zig").Token;
const RegexError = @import("types.zig").RegexError;
const TokenType = @import("types.zig").TokenType;

pub fn print(self: Regex, writer: anytype) !void {
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
