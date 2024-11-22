const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const MigrateOpts = struct {
    rootPath: []const u8,
};

pub fn migrate(opts: MigrateOpts) !void {
    var dir = try std.fs.cwd().openDir(opts.rootPath, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |item| {
        std.debug.print("file: {s}\n", .{item.name});
    }
}

test "test" {
    try migrate(.{ .rootPath = "." });
}
