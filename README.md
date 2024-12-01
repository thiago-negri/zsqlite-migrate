# zsqlite-migrate

Apply SQL migration files to a SQLite database.


## Notes

- All files in `migration_root_path` will be loaded at compile time and will be embedded in your executable.
- Order is determined by filename.
- Option `minify_sql` can be set to `true` to minify all migration SQLs before embedding them into the executable.
- The last statement in a migration file must not include the `;` (unless `minify_sql`).  Otherwise we will try to
  execute the white space after the last `;` as if it was a new statement and SQLite will return an error (MISUSE).
  If `minify_sql` option is set to `true`, the last `;` is automatically dropped for you.
- Previously executed files are ignored.
- Table `z_migrate` is used for control, created automatically on first run.
- Migrations are applied outside transactions, so if a migration file contains multiple statements and one of them
  fails, it's up to you to recover the database.  If you want to be on the safe side, use a single statement in each
  migration file, then you know exactly which statement failed.


## Install

Add as a dependency:

```sh
zig fetch --save "https://github.com/thiago-negri/zsqlite-migrate/archive/refs/heads/master.zip"
```

Add to your build:

```zig
// Add SQLite Migrate
const zsqlite_migrate = b.dependency("zsqlite-migrate", .{
    .target = target,
    .optimize = optimize,
    .migration_root_path = @as([]const u8, "./migrations/"), // From where it will load migration files
    .minify_sql = true, // Whether we minify the SQL before embedding it
});
const zsqlite_migrate_module = zsqlite_migrate.module("zsqlite-migrate");
exe.root_module.addImport("zsqlite-migrate", zsqlite_migrate_module);
```


## Use

```zig
const migrate = @import("zsqlite-migrate").migrate;
const c = @cImport({
    @cInclude("sqlite3.h")
});

const db: *c.sqlite3 = ...; // your SQLite connection
// execute migrations (emit_debug=true will print executions to std.debug)
try migrate(db, .{ .emit_debug = true });
```

*Recommended:* Add a migration test to a in-memory database to your project to make sure all migrations work on a
fresh database.

```zig
test "migrate" {
  var opt_db: ?*c.sqlite3 = null;
  defer if (opt_db) |db| {
    _ = c.sqlite3_close(db);
  };
  const err = c.sqlite3_open(":memory:", &opt_db);
  try std.testing.expectEqual(c.SQLITE_OK, err);
  if (opt_db) |db| {
    try migrate(db, .{ .emit_debug = true });
  } else {
    try std.testing.expect(false);
  }
}
```

See [zsqlite-demo](https://github.com/thiago-negri/zsqlite-demo) for an example on how to use on a "full" project.



## Tests

```sh
zig build test -Dmigration_root_path=./tests/migrations/ -Dminify_sql
```
