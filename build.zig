const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check_migration_files = b.option(bool, "check_migration_files", "Whether we do runtime checks for migration files that contains more than one statement, defaults to true") orelse true;

    const options = b.addOptions();
    options.addOption(bool, "check_migration_files", check_migration_files);

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
