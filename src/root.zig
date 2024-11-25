const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn migrate(sqlite3: *c.sqlite3, rootPath: []const u8, allocator: std.mem.Allocator) !void {
    var stmt_read: ?*c.sqlite3_stmt = null;
    defer if (stmt_read) |ptr| {
        _ = c.sqlite3_finalize(ptr);
    };
    var stmt_insert: ?*c.sqlite3_stmt = null;
    defer if (stmt_insert) |ptr| {
        _ = c.sqlite3_finalize(ptr);
    };

    var filename_sql: ?[]const u8 = null;

    const exists = try zMigrateTableExists(sqlite3);
    if (!exists) {
        try zMigrateTableCreate(sqlite3);
    } else {
        stmt_read = try zMigratePrepareRead(sqlite3);
        filename_sql = try zMigrateStep(stmt_read.?);
    }

    var dir = try std.fs.cwd().openDir(rootPath, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |file| {
        if (file.kind != .file) {
            continue;
        }
        const filename_dir = file.name;

        var ord = order(filename_dir, filename_sql);
        while (ord == .gt) : (ord = order(filename_dir, filename_sql)) {
            filename_sql = try zMigrateStep(stmt_read.?);
        }

        if (ord == .lt) {
            const stat = try dir.statFile(filename_dir);
            const size = stat.size + 1; // +1 for sentinel
            const content = try dir.readFileAllocOptions(allocator, filename_dir, size, size, @alignOf(u8), 0);
            defer allocator.free(content);
            try zMigrateApply(sqlite3, content);
            if (stmt_insert == null) {
                stmt_insert = try zMigratePrepareInsert(sqlite3);
            } else {
                const err = c.sqlite3_reset(stmt_insert);
                if (err != c.SQLITE_OK) {
                    return Error.Sqlite;
                }
            }
            try zMigrateInsert(stmt_insert.?, filename_dir);
        }
    }
}

fn zMigrateApply(sqlite3: *c.sqlite3, sql: [:0]const u8) Error!void {
    var stmt: ?*c.sqlite3_stmt = null;
    var tail: ?[*:0]const u8 = null;
    const err = c.sqlite3_prepare_v2(sqlite3, sql.ptr, @intCast(sql.len + 1), &stmt, &tail);
    if (err != c.SQLITE_OK) {
        if (stmt) |ptr| {
            _ = c.sqlite3_finalize(ptr);
        }
        return Error.Sqlite;
    }
    defer _ = c.sqlite3_finalize(stmt);
    if (tail) |ptr| {
        if (ptr[0] != 0) {
            return Error.MigrationMustBeSingleStatement;
        }
    }
    const step = c.sqlite3_step(stmt);
    if (step != c.SQLITE_DONE) {
        return Error.Sqlite;
    }
}

fn zMigratePrepareRead(sqlite3: *c.sqlite3) Error!*c.sqlite3_stmt {
    var stmt: ?*c.sqlite3_stmt = null;
    errdefer if (stmt) |ptr| {
        _ = c.sqlite3_finalize(ptr);
    };
    const sql: [:0]const u8 =
        \\SELECT filename FROM z_migrate ORDER BY filename
    ;
    const err = c.sqlite3_prepare_v2(sqlite3, sql.ptr, @intCast(sql.len + 1), &stmt, null);
    if (err != c.SQLITE_OK) {
        return Error.Sqlite;
    }
    if (stmt) |ptr| {
        return ptr;
    }
    return Error.Sqlite;
}

fn zMigrateStep(stmt: *c.sqlite3_stmt) Error!?[]const u8 {
    const step = c.sqlite3_step(stmt);
    switch (step) {
        c.SQLITE_DONE => {
            return null;
        },
        c.SQLITE_ROW => {
            const data_ptr = c.sqlite3_column_text(stmt, 0);
            const size = @as(usize, @intCast(c.sqlite3_column_bytes(stmt, 0)));
            return data_ptr[0..size];
        },
        else => {
            return Error.Sqlite;
        },
    }
}

fn order(dir: []const u8, opt_sql: ?[]const u8) std.math.Order {
    if (opt_sql) |sql| {
        return std.mem.order(u8, dir, sql);
    } else {
        return .lt;
    }
}

fn zMigratePrepareInsert(sqlite3: *c.sqlite3) Error!*c.sqlite3_stmt {
    const sql: [:0]const u8 =
        \\INSERT INTO z_migrate(filename,applied_at)VALUES(?,?)
    ;
    var stmt: ?*c.sqlite3_stmt = null;
    const err = c.sqlite3_prepare_v2(sqlite3, sql.ptr, @intCast(sql.len + 1), &stmt, null);
    if (err != c.SQLITE_OK) {
        if (stmt) |ptr| {
            _ = c.sqlite3_finalize(ptr);
        }
        return Error.Sqlite;
    }
    if (stmt) |ptr| {
        return ptr;
    }
    return Error.Sqlite;
}

fn zMigrateInsert(stmt: *c.sqlite3_stmt, filename_dir: []const u8) Error!void {
    var err = c.sqlite3_bind_text(stmt, 1, filename_dir.ptr, @intCast(filename_dir.len), c.SQLITE_STATIC);
    if (err != c.SQLITE_OK) {
        return Error.Sqlite;
    }
    const now = std.time.timestamp();
    err = c.sqlite3_bind_int64(stmt, 2, now);
    if (err != c.SQLITE_OK) {
        return Error.Sqlite;
    }
    const step = c.sqlite3_step(stmt);
    switch (step) {
        c.SQLITE_DONE => {
            return;
        },
        else => {
            return Error.Sqlite;
        },
    }
}

pub const Error = error{ Sqlite, MigrationMustBeSingleStatement };

fn zMigrateTableExists(sqlite3: *c.sqlite3) Error!bool {
    const sql: [:0]const u8 =
        \\SELECT 1 FROM sqlite_schema WHERE type='table' AND name='z_migrate'
    ;
    var stmt: ?*c.sqlite3_stmt = null;
    const err = c.sqlite3_prepare_v2(sqlite3, sql.ptr, @intCast(sql.len + 1), &stmt, null);
    if (err != c.SQLITE_OK) {
        if (stmt) |ptr| {
            _ = c.sqlite3_finalize(ptr);
        }
        return Error.Sqlite;
    }
    defer _ = c.sqlite3_finalize(stmt);
    const step = c.sqlite3_step(stmt);
    switch (step) {
        c.SQLITE_DONE => {
            return false;
        },
        c.SQLITE_ROW => {
            return true;
        },
        else => {
            return Error.Sqlite;
        },
    }
}

fn zMigrateTableCreate(sqlite3: *c.sqlite3) Error!void {
    const sql: [:0]const u8 =
        \\CREATE TABLE z_migrate(filename TEXT,applied_at INTEGER)
    ;
    var stmt: ?*c.sqlite3_stmt = null;
    const err = c.sqlite3_prepare_v2(sqlite3, sql.ptr, @intCast(sql.len + 1), &stmt, null);
    if (err != c.SQLITE_OK) {
        if (stmt) |ptr| {
            _ = c.sqlite3_finalize(ptr);
        }
        return Error.Sqlite;
    }
    defer _ = c.sqlite3_finalize(stmt);
    const step = c.sqlite3_step(stmt);
    switch (step) {
        c.SQLITE_DONE => {
            return;
        },
        else => {
            return Error.Sqlite;
        },
    }
}

test "test" {
    var sqlite3: ?*c.sqlite3 = null;
    errdefer {
        const sqlite_errcode = c.sqlite3_extended_errcode(sqlite3);
        const sqlite_errmsg = c.sqlite3_errmsg(sqlite3);
        std.debug.print("{d}: {s}\n", .{ sqlite_errcode, sqlite_errmsg });
    }
    defer if (sqlite3) |ptr| {
        _ = c.sqlite3_close(ptr);
    };
    var err = c.sqlite3_open(":memory:", &sqlite3);
    try std.testing.expect(err == c.SQLITE_OK);
    try zMigrateTableCreate(sqlite3.?);
    {
        const stmt: *c.sqlite3_stmt = try zMigratePrepareInsert(sqlite3.?);
        defer _ = c.sqlite3_finalize(stmt);
        try zMigrateInsert(stmt, "1_one.sql");
        _ = c.sqlite3_reset(stmt);
        try zMigrateInsert(stmt, "3_three.sql");
        _ = c.sqlite3_reset(stmt);
        try zMigrateInsert(stmt, "7_seven.sql");
    }
    try migrate(sqlite3.?, "./tests/migrations", std.testing.allocator);
    {
        const sql: [:0]const u8 =
            \\SELECT name FROM sqlite_schema WHERE type='table' ORDER BY name
        ;
        var stmt: ?*c.sqlite3_stmt = null;
        err = c.sqlite3_prepare_v2(sqlite3, sql, @intCast(sql.len + 1), &stmt, null);
        try std.testing.expect(err == c.SQLITE_OK);
        defer _ = c.sqlite3_finalize(stmt);
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        var name = c.sqlite3_column_text(stmt, 0);
        var size: usize = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "five", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "four", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "six", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "two", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "z_migrate", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_DONE);
    }
    {
        const sql: [:0]const u8 =
            \\SELECT filename FROM z_migrate ORDER BY filename
        ;
        var stmt: ?*c.sqlite3_stmt = null;
        err = c.sqlite3_prepare_v2(sqlite3, sql, @intCast(sql.len + 1), &stmt, null);
        try std.testing.expect(err == c.SQLITE_OK);
        defer _ = c.sqlite3_finalize(stmt);
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        var name = c.sqlite3_column_text(stmt, 0);
        var size: usize = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "1_one.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "2_two.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "3_three.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "4_four.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "5_five.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "6_six.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_ROW);
        name = c.sqlite3_column_text(stmt, 0);
        size = @intCast(c.sqlite3_column_bytes(stmt, 0));
        try std.testing.expect(std.mem.eql(u8, "7_seven.sql", name[0..size]));
        err = c.sqlite3_step(stmt);
        try std.testing.expect(err == c.SQLITE_DONE);
    }
}
