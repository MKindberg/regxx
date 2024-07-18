const std = @import("std");

const Registry = struct {
    name: []const u8 = "regxx",
    description: []const u8 = "Explain regular expressions",
    homepage: []const u8 = "https://github.com/mkindberg/regxx",
    licenses: []const []const u8 = &[_][]const u8{"MIT"},
    languages: []const []const u8 = &[_][]const u8{},
    categories: []const []const u8 = &[_][]const u8{"LSP"},
    source: Source = .{},
    bin: Bin = .{},

    const Source = struct {
        id: []const u8 = "pkg:github/mkindberg/regxx@unknown",
        asset: []const Asset = &[_]Asset{Asset{}},
    };
    const Bin = struct {
        @"censor-ls": []const u8 = "{{source.asset.bin}}",
    };
    const Asset = struct {
        target: []const u8 = "linux_x64",
        file: []const u8 = "regxx",
        bin: []const u8 = "regxx",
    };

    const Self = @This();
    fn init(allocator: std.mem.Allocator, version: []const u8) !Self {
        const id = try std.fmt.allocPrint(allocator, "pkg:github/mkindberg/regxx@{s}", .{version});
        return Registry{ .source = .{ .id = id } };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const registry = try Registry.init(allocator, @embedFile("version"));
    defer allocator.free(registry.source.id);

    var registry_file = try std.fs.cwd().createFile("registry.json", .{});
    defer registry_file.close();
    const regs = [_]Registry{registry};
    try std.json.stringify(regs, .{ .whitespace = .indent_2 }, registry_file.writer());
}
