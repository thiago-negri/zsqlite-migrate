const std = @import("std");

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

// Hacky, but works for me
fn minifySql(alloc: std.mem.Allocator, sql: [:0]const u8) ![:0]const u8 {
    const MinifySqlMode = enum { identifier, string, whitespace, line_comment, multiline_comment };

    // Store every "useful word" here, it should countain every sequence
    // of chars from the original SQL, except whitespace and comments.
    var array = std.ArrayList([]const u8).init(alloc);
    defer array.deinit();

    // Populate the array of "useful words"
    var mode: MinifySqlMode = .whitespace;
    var identifier_start_index: usize = 0;
    var current_index: usize = 0;
    var escape = false;
    var string_char: u8 = 0;
    while (current_index < sql.len) : (current_index += 1) {
        const char = sql[current_index];
        switch (mode) {
            .identifier => {
                switch (char) {
                    '0'...'9', 'A'...'Z', 'a'...'z', '_', ')', '(', ',', ';', '=' => {
                        // ignore
                    },
                    else => {
                        const identifier = sql[identifier_start_index..current_index];
                        try array.append(identifier);

                        // We may have hit a "-", a "/" so we need to re-evaluate it to check if we
                        // are starting a comment.  That's why we rewind the current index by one.
                        mode = .whitespace;
                        current_index -= 1;
                    },
                }
            },
            .string => {
                if (!escape) {
                    if (char == string_char) {
                        const identifier = sql[identifier_start_index .. current_index + 1];
                        try array.append(identifier);
                        mode = .whitespace;
                    } else if (char == '\\') {
                        escape = true;
                    }
                } else {
                    escape = false;
                }
            },
            .whitespace => {
                switch (char) {
                    '"', '\'' => {
                        mode = .string;
                        string_char = char;
                        identifier_start_index = current_index;
                    },
                    '-' => {
                        if (current_index + 1 < sql.len and sql[current_index + 1] == '-') {
                            mode = .line_comment;
                            current_index += 1;
                        } else {
                            mode = .identifier;
                            identifier_start_index = current_index;
                        }
                    },
                    '/' => {
                        if (current_index + 1 < sql.len and sql[current_index + 1] == '*') {
                            mode = .multiline_comment;
                        } else {
                            mode = .identifier;
                            identifier_start_index = current_index;
                        }
                    },
                    ' ', '\r', '\t', '\n' => {
                        // ignore
                    },
                    else => {
                        mode = .identifier;
                        identifier_start_index = current_index;
                    },
                }
            },
            .line_comment => {
                if (char == '\n') {
                    mode = .whitespace;
                }
            },
            .multiline_comment => {
                if (char == '*' and current_index + 1 < sql.len and sql[current_index + 1] == '/') {
                    mode = .whitespace;
                    current_index += 1;
                }
            },
        }
    }

    // Calculate the total number of bytes we will need for the minified SQL
    var total_length: usize = 0;
    var require_space_after = false;
    for (array.items) |item| {
        if (total_length > 0) {
            const first_char = item[0];
            switch (first_char) {
                ')', '(', ',', ';', '=' => {
                    // ignore
                },
                else => {
                    if (require_space_after) {
                        total_length += 1;
                    }
                },
            }
        }

        total_length += item.len;

        const last_char = item[item.len - 1];
        switch (last_char) {
            ')', '(', ',', ';', '=' => {
                require_space_after = false;
            },
            else => {
                require_space_after = true;
            },
        }
    }
    const last_item = array.items[array.items.len - 1];
    if (last_item[last_item.len - 1] == ';') {
        total_length -= 1;
    }

    // Copy each identifier slice into a new minified SQL resulting string
    var minified_sql: [:0]u8 = try alloc.allocWithOptions(u8, total_length, null, 0);
    current_index = 0;
    for (array.items) |item| {
        if (total_length > 0) {
            const first_char = item[0];
            switch (first_char) {
                ')', '(', ',', ';', '=' => {
                    // ignore
                },
                else => {
                    if (require_space_after) {
                        minified_sql[current_index] = ' ';
                        current_index += 1;
                    }
                },
            }
        }

        for (minified_sql[current_index .. current_index + item.len], item) |*d, s| d.* = s;
        current_index += item.len;

        const last_char = item[item.len - 1];
        switch (last_char) {
            ')', '(', ',', ';', '=' => {
                require_space_after = false;
            },
            else => {
                require_space_after = true;
            },
        }
    }
    // Make sure we end with the sentinel (this will also overwrite the last ';' if present)
    // Leaving a ';' at the end will make the migration try to apply an empty SQL after, which causes a MISUSE error
    // on SQLite
    minified_sql[total_length] = 0;

    // std.debug.print("{s}\n", .{minified_sql});

    return minified_sql;
}
