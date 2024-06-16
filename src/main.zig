const std = @import("std");
const lsp = @import("lsp");
const lsp_types = @import("lsp").types;
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

    const home = std.posix.getenv("HOME").?;
    var buf: [256]u8 = undefined;

    const log_path = try std.fmt.bufPrint(&buf, "{s}/.local/share/regEx-ls/log.txt", .{home});
    std.fs.makeDirAbsolute(std.fs.path.dirname(log_path).?) catch {};
    try Logger.init(log_path);
    defer Logger.deinit();

    var state = State.init(allocator);
    defer state.deinit();

    const server_data = lsp_types.ServerData{
        .capabilities = .{
            .textDocumentSync = 2,
            .hoverProvider = true,
        },
        .serverInfo = .{
            .name = "regEx-ls",
            .version = "0.1.0",
        },
    };
    var server = lsp.Lsp(State).init(allocator, server_data, &state);

    server.registerDocOpenCallback(handleOpenDoc);
    server.registerDocChangeCallback(handleChangeDoc);
    server.registerDocCloseCallback(handleCloseDoc);
    server.registerHoverCallback(handleHover);

    return server.start();
}

fn handleOpenDoc(_: std.mem.Allocator, state: *State, params: lsp_types.Notification.DidOpenTextDocument.Params) void {
    const doc = params.textDocument;
    std.log.info("Opened {s}", .{doc.uri});
    std.log.debug("{s}", .{doc.text});
    state.openDocument(doc.uri, doc.text) catch unreachable;
}

fn handleChangeDoc(_: std.mem.Allocator, state: *State, params: lsp_types.Notification.DidChangeTextDocument.Params) void {
    for (params.contentChanges) |change| {
        state.updateDocument(params.textDocument.uri, change.text, change.range) catch unreachable;
    }

    std.log.debug("Updated document {s}", .{state.documents.get(params.textDocument.uri).?.doc.text});
}

fn handleCloseDoc(_: std.mem.Allocator, state: *State, params: lsp_types.Notification.DidCloseTextDocument.Params) void {
    state.closeDocument(params.textDocument.uri);
}

fn handleHover(allocator: std.mem.Allocator, state: *State, request: lsp_types.Request.Hover.Params, id: i32) void {
    if (state.hover(allocator,id, request.textDocument.uri, request.position)) |response| {
        defer allocator.free(response.result.contents);
        lsp.writeResponse(allocator, response) catch unreachable;

        std.log.info("Sent Hover response", .{});
    }
}
