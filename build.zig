const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zsqlite_migrate_mod = b.addModule("zsqlite-migrate", .{
        .root_source_file = b.path("src/root.zig"),
    });

    // Add SQLite C as a static library.
    const zsqlite_c = b.dependency("zsqlite-c", .{ .target = target, .optimize = optimize });
    const zsqlite_c_artifact = zsqlite_c.artifact("zsqlite-c");
    zsqlite_migrate_mod.linkLibrary(zsqlite_c_artifact);

    const zsqlite_migrate_mod_test = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zsqlite_migrate_mod_test.linkLibrary(zsqlite_c_artifact);

    const run_zsqlite_migrate_mod_test = b.addRunArtifact(zsqlite_migrate_mod_test);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_zsqlite_migrate_mod_test.step);
}
