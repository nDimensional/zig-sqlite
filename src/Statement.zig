const std = @import("std");

const c = @import("c.zig");
const errors = @import("errors.zig");
const Database = @import("Database.zig");

const Statement = @This();

ptr: ?*c.sqlite3_stmt,

pub fn prepare(db: Database, sql: []const u8) !Statement {
    var ptr: ?*c.sqlite3_stmt = null;
    try errors.throw(c.sqlite3_prepare_v2(db.ptr, sql.ptr, @intCast(sql.len), &ptr, null));
    return .{ .ptr = ptr };
}

pub fn finalize(stmt: Statement) !void {
    try errors.throw(c.sqlite3_finalize(stmt.ptr));
}

pub fn reset(stmt: Statement) !void {
    try errors.throw(c.sqlite3_reset(stmt.ptr));
}

pub fn clear(stmt: Statement) !void {
    try errors.throw(c.sqlite3_clear_bindings(stmt.ptr));
}

pub fn bindBlob(stmt: Statement, idx: c_int, data: []const u8) !void {
    try errors.throw(c.sqlite3_bind_blob64(stmt.ptr, idx, data.ptr, @intCast(data.len), c.SQLITE_STATIC));
}

pub fn bindDouble(stmt: Statement, idx: c_int, value: f64) !void {
    try errors.throw(c.sqlite3_bind_double(stmt.ptr, idx, value));
}

pub fn bindInt(stmt: Statement, idx: c_int, value: i32) !void {
    try errors.throw(c.sqlite3_bind_int(stmt.ptr, idx, value));
}

pub fn bindInt64(stmt: Statement, idx: c_int, value: i64) !void {
    try errors.throw(c.sqlite3_bind_int64(stmt.ptr, idx, value));
}

pub fn bindNull(stmt: Statement, idx: c_int) !void {
    try errors.throw(c.sqlite3_bind_null(stmt.ptr, idx));
}

pub fn bindText(stmt: Statement, idx: c_int, data: []const u8) !void {
    try errors.throw(c.sqlite3_bind_text64(stmt.ptr, idx, data.ptr, @intCast(data.len), c.SQLITE_STATIC, c.SQLITE_UTF8));
}

pub fn step(stmt: Statement) !bool {
    return switch (c.sqlite3_step(stmt.ptr)) {
        c.SQLITE_ROW => true,
        c.SQLITE_DONE => false,
        else => |code| errors.getError(code),
    };
}

pub fn columnBlob(stmt: Statement, idx: c_int) []const u8 {
    const ptr: [*]const u8 = @intCast(c.sqlite3_column_blob(stmt.ptr, idx));
    const len = c.sqlite3_column_bytes(stmt.ptr, idx);
    return ptr[0..len];
}

pub fn columnDouble(stmt: Statement, idx: c_int) f64 {
    return c.sqlite3_column_double(stmt.ptr, idx);
}

pub fn columnInt(stmt: Statement, idx: c_int) i32 {
    return c.sqlite3_column_int(stmt.ptr, idx);
}

pub fn columnInt64(stmt: Statement, idx: c_int) i64 {
    return c.sqlite3_column_int64(stmt.ptr, idx);
}

pub fn columnText(stmt: Statement, idx: c_int) []const u8 {
    const ptr: [*]const u8 = @intCast(c.sqlite3_column_text(stmt.ptr, idx));
    const len = c.sqlite3_column_bytes(stmt.ptr, idx);
    return ptr[0..len];
}
