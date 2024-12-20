const std = @import("std");
const minifySql = @import("zsqlite-minify").minifySql;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const migration_root_path_desc =
        \\The root path where all the migration SQL files are
    ;
    const migration_root_path = b.option([]const u8, "migration_root_path", migration_root_path_desc);

    const minify_sql_desc =
        \\Minify the migration SQL before embedding it, defaults to false
    ;
    const minify_sql = b.option(bool, "minify_sql", minify_sql_desc);

    // Load migration files into a config module
    var files = std.ArrayList([]const u8).init(b.allocator);
    defer files.deinit();
    var sqls = std.ArrayList([:0]const u8).init(b.allocator);
    defer sqls.deinit();
    if (migration_root_path) |path| {
        var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();
        var iter = dir.iterate();
        while (try iter.next()) |file| {
            if (file.kind != .file) {
                continue;
            }
            try files.append(b.dupe(file.name));
            const stat = try dir.statFile(file.name);
            const size = stat.size + 1; // +1 for sentinel
            const sql = try dir.readFileAllocOptions(b.allocator, file.name, size, size, @alignOf(u8), 0);
            if (minify_sql orelse false) {
                defer b.allocator.free(sql);
                const minified_sql = try minifySql(b.allocator, sql);
                try sqls.append(minified_sql);
            } else {
                try sqls.append(sql);
            }
        }
    }

    const options = b.addOptions();
    options.addOption([]const []const u8, "migration_filenames", files.items);
    options.addOption([]const [:0]const u8, "migration_sqls", sqls.items);

    const zsqlite_c = b.dependency("zsqlite-c", .{ .target = target, .optimize = optimize });
    const zsqlite_c_artifact = zsqlite_c.artifact("zsqlite-c");

    const zsqlite_migrate_mod = b.addModule("zsqlite-migrate", .{
        .root_source_file = b.path("src/root.zig"),
    });
    zsqlite_migrate_mod.addOptions("config", options);
    zsqlite_migrate_mod.linkLibrary(zsqlite_c_artifact);

    const zsqlite_migrate_mod_test = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zsqlite_migrate_mod_test.linkLibrary(zsqlite_c_artifact);
    zsqlite_migrate_mod_test.root_module.addImport("config", options.createModule());

    const run_zsqlite_migrate_mod_test = b.addRunArtifact(zsqlite_migrate_mod_test);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_zsqlite_migrate_mod_test.step);
}
