const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check_files_desc =
        \\Whether we do runtime checks for migration files that contains more than one statement, defaults to true
    ;
    const check_files = b.option(bool, "check_files", check_files_desc) orelse true;

    const emit_debug_desc =
        \\Whether we emit debug messages for each migration file being applied, defaults to true
    ;
    const emit_debug = b.option(bool, "emit_debug", emit_debug_desc) orelse true;

    const migration_root_path_desc =
        \\The root path where all the migration SQL files are
    ;
    const migration_root_path = b.option([]const u8, "migration_root_path", migration_root_path_desc);

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
            try sqls.append(sql);
        }
    }

    const options = b.addOptions();
    options.addOption(bool, "check_files", check_files);
    options.addOption(bool, "emit_debug", emit_debug);
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
