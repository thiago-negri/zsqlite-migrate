# zsqlite-migrate

Small module to apply SQL migration files to a SQLite database.

## Install

Add as a dependency:

```sh
zig fetch --save "https://github.com/thiago-negri/zsqlite-migrate/archive/refs/heads/master.zip"
```

Add to your build:

```zig
// Add SQLite Migrate
const zsqlite_migrate = b.dependency("zsqlite-migrate", .{ .target = target, .optimize = optimize });
const zsqlite_migrate_module = zsqlite_migrate.module("zsqlite-migrate");
exe.root_module.addImport("zsqlite-migrate", zsqlite_migrate_module);
```

## Use

```zig
const migrate = @import("zsqlite-migrate").migrate;
const c = @cImport({
    @cInclude("sqlite3.h")
});

const path = "./migrations";         // where your SQL files are located
const db: *c.sqlite3 = ...;          // your SQLite connection
const allocator = ...;               // allocator is used to read each file
try migrate(db, path, allocator);    // execute migrations
```

## Notes

- All files in the path will be executed in order, regardless of extension.
- Order is determined by filename.
- Previously executed files are ignored.
- Table `z_migrate` is used for control, created automatically on first run.
- Allocator is only used to read each file into memory, one file at a time.
  Free is called as soon after that file is executed.
- Each migration file must consist of a single SQL statement, without the ending `;`.
    - You can disable that check with `-Dcheck_migration_files=false`, but it will still only
      execute the first statement of each file.
