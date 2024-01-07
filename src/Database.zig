const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");

const Database = @This();

pub const Options = struct {
    mode: enum { ReadWrite, ReadOnly } = .ReadWrite,
    create: bool = true,
};

ptr: ?*c.sqlite3,

pub fn openZ(filename: ?[*:0]const u8, options: Options) !Database {
    var ptr: ?*c.sqlite3 = null;

    var flags: c_int = 0;
    switch (options.mode) {
        .ReadOnly => {
            flags |= c.SQLITE_OPEN_READONLY;
        },
        .ReadWrite => {
            flags |= c.SQLITE_OPEN_READWRITE;
            if (options.create) {
                flags |= c.SQLITE_OPEN_CREATE;
            }
        },
    }

    try errors.throw(c.sqlite3_open_v2(filename, &ptr, flags, null));

    return .{ .ptr = ptr };
}

pub fn close(db: Database) !void {
    try errors.throw(c.sqlite3_close(db.ptr));
}
