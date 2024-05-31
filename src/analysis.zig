const std = @import("std");
const lsp = @import("lsp.zig");
const Document = @import("document.zig").Document;

pub const State = struct {
    allocator: std.mem.Allocator,
    documents: std.StringHashMap(DocData),

    pub fn init(allocator: std.mem.Allocator) State {
        return State{
            .allocator = allocator,
            .documents = std.StringHashMap(DocData).init(allocator),
        };
    }
    pub fn deinit(self: *State) void {
        var it = self.documents.iterator();
        while (it.next()) |i| {
            self.allocator.free(i.key_ptr.*);
            i.value_ptr.deinit();
        }
        self.documents.deinit();
    }

    pub fn openDocument(self: *State, name: []const u8, content: []const u8) !void {
        const key = try self.allocator.alloc(u8, name.len);
        std.mem.copyForwards(u8, key, name);
        const doc = try DocData.init(self.allocator, content);

        try self.documents.put(key, doc);
    }

    pub fn closeDocument(self: *State, name: []const u8) void {
        const entry = self.documents.fetchRemove(name);
        self.allocator.free(entry.?.key);
        entry.?.value.deinit();
    }

    pub fn updateDocument(self: *State, name: []const u8, text: []const u8, range: lsp.Range) !void {
        var doc = self.documents.getPtr(name).?;
        try doc.doc.update(text, range);
    }

    pub fn hover(self: *State, id: i32, uri: []u8, pos: lsp.Position) ?lsp.Response.Hover {
        // const doc = self.documents.get(uri).?;
        _ = uri;
        _ = pos;
        _ = self;
        return lsp.Response.Hover.init(id, "hover");
    }
    pub fn free(self: *State, buf: []const u8) void {
        self.allocator.free(buf);
    }
};

const DocData = struct {
    doc: Document,

    const Self = @This();
    fn init(allocator: std.mem.Allocator, content: []const u8) !Self {
        const doc = try Document.init(allocator, content);

        const self = Self{ .doc = doc };

        return self;
    }

    fn deinit(self: DocData) void {
        self.doc.deinit();
    }
};
