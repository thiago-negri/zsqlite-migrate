# zsqlite-migrate

Small module to apply SQL migration files to a SQLite database.

## Notes

- All files in `migration_root_path` will be loaded at compile time and will be embedded in your executable.
- Order is determined by filename.
- The last statement in a migration file must not include the `;`.  Otherwise we will try to execute the white space
  after the last `;` as if it was a new statement and SQLite will return an error (MISUSE).  I don't want to check for
  whitespaces before executing the migration (one idea is to include a preprocessor that minifies SQL before bundling
  it into the executable).
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
    .emit_debug = true // Whether or not we emit debug message for each SQL migration being applied
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

const db: *c.sqlite3 = ...;          // your SQLite connection
try migrate(db);                     // execute migrations
```

See [zsqlite-demo](https://github.com/thiago-negri/zsqlite-demo) for an example on how to use on a "full" project.

## Tests

```sh
zig build test -Dmigration_root_path=./tests/migrations/
```
