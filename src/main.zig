const std = @import("std");
const rpc = @import("rpc.zig");
const lsp = @import("lsp.zig");
const Reader = @import("reader.zig").Reader;
const State = @import("analysis.zig").State;

const Logger = @import("logger.zig").Logger;

const builtin = @import("builtin");

pub const std_options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = Logger.log,
};

pub const RunState = enum {
    Run,
    ShutdownOk,
    ShutdownErr,
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdin = std.io.getStdIn().reader();

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/regEx-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    var reader = Reader.init(allocator, stdin);
    defer reader.deinit();

    var state = State.init(allocator);
    defer state.deinit();

    var header = std.ArrayList(u8).init(allocator);
    defer header.deinit();
    var content = std.ArrayList(u8).init(allocator);
    defer content.deinit();

    var run_state = RunState.Run;
    while (run_state == RunState.Run) {
        std.log.info("Waiting for header", .{});
        _ = try reader.readUntilDelimiterOrEof(header.writer(), "\r\n\r\n");

        const content_len_str = "Content-Length: ";
        const content_len = if (std.mem.indexOf(u8, header.items, content_len_str)) |idx|
            try std.fmt.parseInt(usize, header.items[idx + content_len_str.len ..], 10)
        else {
            _ = try std.io.getStdErr().write("Content-Length not found in header\n");
            break;
        };
        header.clearRetainingCapacity();

        const bytes_read = try reader.readN(content.writer(), content_len);
        if (bytes_read != content_len) {
            break;
        }
        defer content.clearRetainingCapacity();

        const decoded = rpc.decodeMessage(allocator, content.items) catch |e| {
            std.log.info("Failed to decode message: {any}\n", .{e});
            continue;
        };
        run_state = try handleMessage(allocator, &state, decoded);
    }
    return @intFromBool(run_state == RunState.ShutdownOk);
}

fn writeResponse(allocator: std.mem.Allocator, msg: anytype) !void {
    const response = try rpc.encodeMessage(allocator, msg);
    defer response.deinit();

    const writer = std.io.getStdOut().writer();
    _ = try writer.write(response.items);
    std.log.info("Sent response", .{});
}

fn handleMessage(allocator: std.mem.Allocator, state: *State, msg: rpc.DecodedMessage) !RunState {
    const local_state = struct {
        var shutdown = false;
    };

    std.log.info("Received request: {s}", .{msg.method.toString()});

    if (local_state.shutdown and msg.method != rpc.MethodType.Exit) {
        return try handleShutingDown(allocator, msg.method, msg.content);
    }
    switch (msg.method) {
        rpc.MethodType.Initialize => {
            try handleInitialize(allocator, msg.content);
        },
        rpc.MethodType.Initialized => {},
        rpc.MethodType.TextDocument_DidOpen => {
            try handleOpenDoc(allocator, state, msg.content);
        },
        rpc.MethodType.TextDocument_DidChange => {
            try handleChangeDoc(allocator, state, msg.content);
        },
        rpc.MethodType.TextDocument_DidClose => {
            try handleCloseDoc(allocator, state, msg.content);
        },
        rpc.MethodType.TextDocument_Hover => {
            try handleHover(allocator, state, msg.content);
        },
        rpc.MethodType.Shutdown => {
            try handleShutdown(allocator, msg.content);
            local_state.shutdown = true;
        },
        rpc.MethodType.Exit => {
            return RunState.ShutdownErr;
        },
    }
    return RunState.Run;
}

fn handleInitialize(allocator: std.mem.Allocator, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Request.Initialize, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const request = parsed.value;

    const client_info = request.params.clientInfo.?;
    std.log.info("Connected to {s} {s}", .{ client_info.name, client_info.version });

    const response_msg = lsp.Response.Initialize.init(request.id);

    try writeResponse(allocator, response_msg);
}

fn handleOpenDoc(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Notification.DidOpenTextDocument, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const doc = parsed.value.params.textDocument;
    std.log.info("Opened {s}", .{doc.uri});
    std.log.debug("{s}", .{doc.text});
    try state.openDocument(doc.uri, doc.text);
}

fn handleChangeDoc(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Notification.DidChangeTextDocument, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const doc_params = parsed.value.params;

    for (doc_params.contentChanges) |change| {
        try state.updateDocument(doc_params.textDocument.uri, change.text, change.range);
    }

    std.log.debug("Updated document {s}", .{state.documents.get(doc_params.textDocument.uri).?.doc.text});
}

fn handleCloseDoc(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Notification.DidCloseTextDocument, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    state.closeDocument(parsed.value.params.textDocument.uri);
}

fn handleHover(allocator: std.mem.Allocator, state: *State, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Request.Hover, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const request = parsed.value;

    if (state.hover(request.id, request.params.textDocument.uri, request.params.position)) |response| {
        try writeResponse(allocator, response);

        std.log.info("Sent Hover response", .{});
    }
}

fn handleShutdown(allocator: std.mem.Allocator, msg: []const u8) !void {
    const parsed = try std.json.parseFromSlice(lsp.Request.Shutdown, allocator, msg, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const response = lsp.Response.Shutdown.init(parsed.value);
    try writeResponse(allocator, response);
}

fn handleShutingDown(allocator: std.mem.Allocator, method_type: rpc.MethodType, msg: []const u8) !RunState {
    if (method_type == rpc.MethodType.Exit) {
        return RunState.ShutdownOk;
    }

    const parsed = std.json.parseFromSlice(lsp.Request.Request, allocator, msg, .{ .ignore_unknown_fields = true });

    if (parsed) |request| {
        const reply = lsp.Response.Error.init(request.value.id, lsp.ErrorCode.InvalidRequest, "Shutting down");
        try writeResponse(allocator, reply);
        request.deinit();
    } else |err| if (err == error.UnknownField) {
        const reply = lsp.Response.Error.init(0, lsp.ErrorCode.InvalidRequest, "Shutting down");
        try writeResponse(allocator, reply);
    }
    return RunState.Run;
}
