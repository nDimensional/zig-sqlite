# zig-sqlite

Simple, low-level, explicitly-typed SQLite bindings for Zig.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
  - [Methods](#methods)
  - [Queries](#queries)
- [Notes](#notes)
- [Build options](#build-options)
- [License](#license)

## Installation

This library uses the new per-module compilation features and requires Zig version `0.12.0-dev.2127+fcc0c5ddc` (2023-01-10) or later.

Add the dependency to `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .sqlite = .{
            .url = "https://github.com/nDimensional/zig-sqlite/archive/refs/tags/v0.0.3.tar.gz",
            .hash = "1220fc48d43fb4024ce19ae3790e05a599d319d7997983fff1c38a5a8080a73a1138",
        },
    },
}
```

Then add `sqlite` as an import to your root modules in `build.zig`:

```zig
fn build(b: *std.Build) void {
    const app = b.addExecutable(.{ ... });
    // ...

    const sqlite = b.dependency("sqlite", .{});
    app.root_module.addImport("sqlite", sqlite.module("sqlite"));
}
```

## Usage

Open databases using `Database.init` and close them with `db.deinit()`:

```zig
const sqlite = @import("sqlite");

{
    // in-memory database
    const db = try sqlite.Database.init(.{});
    defer db.deinit();
}

{
    // persistent database
    const db = try sqlite.Database.init(.{ .path = "path/to/db.sqlite" });
    defer db.deinit();
}
```

Execute one-off statements using `Database.exec`:

```zig
try db.exec("CREATE TABLE users (id TEXT PRIMARY KEY, age FLOAT)", .{});
```

Prepare statements using `Database.prepare`, and finalize them with `stmt.deinit()`. Statements must be given explicit comptime params and result types and are typed as `sqlite.Statement(Params, Result)`.

- The comptime `Params` type must be a struct whose fields are (possibly optional) float, integer, `sqlite.Blob`, or `sqlite.Text` types.
- The comptime `Result` type must either be `void`, indicating a method that returns no data, or a struct of the same kind as param types, indicating a query that returns rows.

`Blob` and `Text` are wrapper structs with a single field `data: []const u8`.

### Methods

If the `Result` type is `void`, use the `exec(params: Params): !void` method to execute the statement several times with different params.

```zig
const User = struct { id: sqlite.Text, age: ?f32 };
const insert = try db.prepare(
    User,
    void,
    "INSERT INTO users VALUES (:id, :age)",
);
defer insert.deinit();

try insert.exec(.{ .id = sqlite.text("a"), .age = 21 });
try insert.exec(.{ .id = sqlite.text("b"), .age = null });
```

### Queries

If the `Result` type is a struct, use `stmt.bind(params)` in conjunction with `defer stmt.reset()`, then `stmt.step()` over the results.

> ℹ️ Every `bind` should be paired with a `reset`, just like every `init` is paired with a `deinit`.

```zig
const User = struct { id: sqlite.Text, age: ?f32 };
const select = try db.prepare(
    struct { min: f32 },
    User,
    "SELECT * FROM users WHERE age >= :min",
);

defer select.deinit();

// Get a single row
{
    try select.bind(.{ .min = 0 });
    defer select.reset();

    if (try select.step()) |user| {
        // user.id: sqlite.Text
        // user.age: ?f32
        std.log.info("id: {s}, age: {d}", .{ user.id.data, user.age orelse 0 });
    }
}

// Iterate over all rows
{
    try select.bind(.{ .min = 0 });
    defer select.reset();

    while (try select.step()) |user| {
        std.log.info("id: {s}, age: {d}", .{ user.id.data, user.age orelse 0 });
    }
}

// Iterate again, with different params
{
    try select.bind(.{ .min = 21 });
    defer select.reset();

    while (try select.step()) |user| {
        std.log.info("id: {s}, age: {d}", .{ user.id.data, user.age orelse 0 });
    }
}
```

Text and blob values must not be retained across steps. **You are responsible for copying them.**

## Notes

Crafting sensible Zig bindings for SQLite involves making tradeoffs between following the Zig philosophy ("deallocation must succeed") and matching the SQLite API, in which closing databases or finalizing statements may return error codes.

This library takes the following approach:

- `Database.deinit` calls `sqlite3_close_v2` and panics if it returns an error code.
- `Statement.deinit` calls `sqlite3_finalize` and panics if it returns an error code.
- `Statement.step` automatically calls `sqlite3_reset` if `sqlite3_step` returns an error code.
  - In SQLite, `sqlite3_reset` returns the error code from the most recent call to `sqlite3_step`. This is handled gracefully.
- `Statement.reset` calls both `sqlite3_reset` and `sqlite3_clear_bindings`, and panics if either return an error code.

These should only result in panic through gross misuse or in extremely unusual situations, e.g. `sqlite3_reset` failing internally. All "normal" errors are faithfully surfaced as Zig errors.

## Build options

```zig
struct {
    SQLITE_ENABLE_COLUMN_METADATA: bool = false,
    SQLITE_ENABLE_DBSTAT_VTAB:     bool = false,
    SQLITE_ENABLE_FTS3:            bool = false,
    SQLITE_ENABLE_FTS4:            bool = false,
    SQLITE_ENABLE_FTS5:            bool = false,
    SQLITE_ENABLE_GEOPOLY:         bool = false,
    SQLITE_ENABLE_ICU:             bool = false,
    SQLITE_ENABLE_MATH_FUNCTIONS:  bool = false,
    SQLITE_ENABLE_RBU:             bool = false,
    SQLITE_ENABLE_RTREE:           bool = false,
    SQLITE_ENABLE_STAT4:           bool = false,
    SQLITE_OMIT_DECLTYPE:          bool = false,
    SQLITE_OMIT_JSON:              bool = false,
    SQLITE_USE_URI:                bool = false,
}
```

Set these by passing e.g. `-DSQLITE_ENABLE_RTREE` in the CLI, or by setting `.SQLITE_ENABLE_RTREE = true` in the `args` parameter to `std.Build.dependency`. For example:

```zig
pub fn build(b: *std.Build) !void {
    // ...

    const sqlite = b.dependency("sqlite", .{ .SQLITE_ENABLE_RTREE = true });
}
```

## License

MIT © nDimensional Studios
