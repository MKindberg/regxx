const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // Get version
    const version_file = b.addWriteFile("version", getVersion(b));

    // Build app
    const exe = b.addExecutable(.{
        .name = "regxx",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("version", .{
        .root_source_file = version_file.getDirectory().path(b, "version"),
    });

    const regex = b.addModule("regex", .{
        .root_source_file = b.path("src/regex/regex.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("regex", regex);

    const lsp_server = b.dependency( "babel", .{
        .target = target,
        .optimize = optimize,
    });
    const lsp= lsp_server.module("lsp");
    exe.root_module.addImport("lsp", lsp);

    b.installArtifact(exe);

    // Run app
    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Run tests
    var cwd = std.fs.cwd().openDir("src", .{ .iterate = true }) catch unreachable;
    defer cwd.close();
    var walker = cwd.walk(b.allocator) catch unreachable;
    defer walker.deinit();

    const test_step = b.step("test", "Run unit tests");
    while (walker.next() catch unreachable) |entry| {
        if (!std.mem.endsWith(u8, entry.path, ".zig")) continue;
        const tests = b.addTest(.{
            .root_source_file = b.path(b.fmt("src/{s}", .{entry.path})),
            .target = target,
            .optimize = optimize,
        });
        const run_tests = b.addRunArtifact(tests);
        test_step.dependOn(&run_tests.step);
    }
    // Create mason registry
    const registry_generator = b.addExecutable(.{
        .name = "generate_registry",
        .root_source_file = b.path("tools/mason_registry.zig"),
        .target = b.graph.host,
    });
    registry_generator.root_module.addAnonymousImport("version", .{
        .root_source_file = version_file.getDirectory().path(b, "version"),
    });
    const registry_step = b.step("gen_registry", "Generate mason.nvim registry");
    const registry_generation = b.addRunArtifact(registry_generator);
    registry_step.dependOn(&registry_generation.step);
}

fn getVersion(b: *std.Build) []const u8 {
    const res = std.process.Child.run(.{ .allocator = b.allocator, .argv = &[_][]const u8{ "git", "tag", "-l" } }) catch return "unknown";
    const stdout = std.mem.trim(u8, res.stdout, "\n");
    var it = std.mem.splitBackwardsScalar(u8, stdout, '\n');
    while (it.next()) |tag| {
        if (tag.len > 0 and tag[0] != 'v') continue;
        return tag;
    } else unreachable;
}
