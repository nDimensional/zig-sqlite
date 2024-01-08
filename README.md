# zig-sqlite

## API

### Database

```zig

pub const Database = struct {
    pub const Mode = enum { ReadWrite, ReadOnly };

    pub const Options = struct {
        path: ?[*:0]const u8 = null,
        mode: Mode = .ReadWrite,
        create: bool = true,
    };

    pub fn init(options: Options) !Database
    pub fn deinit(db: Database) void

    pub fn exec(db: Database, sql: []const u8, params: anytype) !void

    pub fn prepare(
        db: Database,
        comptime Params: type,
        comptime Result: type,
        sql: []const u8,
    ) !Statement
};
```

### Statement

Statements are

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
