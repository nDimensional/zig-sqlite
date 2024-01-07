const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");
const types = @import("types.zig");

const Database = @import("Database.zig");
const Binding = @import("Binding.zig");

pub fn Query(comptime Params: type, comptime Result: type) type {
    const param_bindings = switch (@typeInfo(Params)) {
        .Struct => |info| Binding.parseFields(info.fields),
        else => @compileError("Params type must be a struct"),
    };

    const column_bindings = switch (@typeInfo(Result)) {
        .Struct => |info| Binding.parseFields(info.fields),
        else => @compileError("Result type must be a struct"),
    };

    return struct {
        const Self = @This();

        ptr: ?*c.sqlite3_stmt = null,
        param_indices: [param_bindings.len]c_int = .{0} ** param_bindings.len,
        column_indices: [column_bindings.len]c_int = .{std.math.maxInt(c_int)} ** column_bindings.len,

        pub fn init(db: Database, sql: []const u8) !Self {
            var query = Self{};
            try errors.throw(c.sqlite3_prepare_v2(db.ptr, sql.ptr, @intCast(sql.len), &query.ptr, null));
            errdefer _ = c.sqlite3_finalize(query.ptr);

            try query.initParams();
            try query.initColumns();
            return query;
        }

        fn initParams(query: *Self) !void {
            const param_count = c.sqlite3_bind_parameter_count(query.ptr);

            var idx: c_int = 1;
            params: while (idx <= param_count) : (idx += 1) {
                const name = c.sqlite3_bind_parameter_name(query.ptr, idx);
                if (name == null) {
                    return error.InvalidParameterName;
                }

                const field_name = std.mem.span(name);
                if (field_name.len == 0) {
                    return error.InvalidParameterName;
                } else switch (field_name[0]) {
                    ':', '$', '@' => {},
                    else => return error.InvalidParameterName,
                }

                inline for (param_bindings, 0..) |binding, i| {
                    if (std.mem.eql(u8, binding.name, field_name[1..])) {
                        if (query.param_indices[i] == 0) {
                            query.param_indices[i] = idx;
                            continue :params;
                        } else {
                            return error.DuplicateParameter;
                        }
                    }
                }

                return error.InvalidParameter;
            }

            for (query.param_indices) |index| {
                if (index == 0) {
                    return error.MissingParameter;
                }
            }
        }

        fn initColumns(query: *Self) !void {
            const column_count = c.sqlite3_column_count(query.ptr);

            var n: c_int = 0;
            columns: while (n < column_count) : (n += 1) {
                const column_name = c.sqlite3_column_name(query.ptr, n);
                if (column_name == null) {
                    return error.InvalidColumnName;
                }

                const name = std.mem.span(column_name);

                inline for (column_bindings, 0..) |binding, i| {
                    if (std.mem.eql(u8, binding.name, name)) {
                        if (query.column_indices[i] == std.math.maxInt(c_int)) {
                            query.column_indices[i] = n;
                            continue :columns;
                        } else {
                            return error.DuplicateColumn;
                        }
                    }
                }
            }

            for (query.column_indices) |index| {
                if (index == std.math.maxInt(c_int)) {
                    return error.InvalidColumn;
                }
            }
        }

        pub fn deinit(query: Self) void {
            switch (c.sqlite3_finalize(query.ptr)) {
                c.SQLITE_OK => {},
                else => |code| @panic(@errorName(errors.getError(code))),
            }
        }

        pub fn clear(query: Self) !void {
            try errors.throw(c.sqlite3_clear_bindings(query.ptr));
        }

        pub fn reset(query: Self) !void {
            try errors.throw(c.sqlite3_reset(query.ptr));
        }

        pub fn get(query: Self, params: Params) !?Result {
            try query.bind(params);
            return query.step();
        }

        pub fn step(query: Self) !?Result {
            switch (c.sqlite3_step(query.ptr)) {
                c.SQLITE_ROW => return try query.parse(),
                c.SQLITE_DONE => return null,
                else => |code| {
                    // sqlite3_reset returns the same `code` we already have,
                    // so the `return` is redundant.
                    try errors.throw(c.sqlite3_reset(query.ptr));
                    return errors.getError(code);
                },
            }
        }

        pub fn bind(query: Self, params: Params) !void {
            try query.reset();
            try query.clear();
            inline for (param_bindings, 0..) |binding, i| {
                const idx = query.param_indices[i];
                if (binding.nullable) {
                    if (@field(params, binding.name)) |value| {
                        switch (binding.kind) {
                            .int32 => try query.bindInt32(idx, @intCast(value)),
                            .int64 => try query.bindInt64(idx, @intCast(value)),
                            .float64 => try query.bindFloat64(idx, @floatCast(value)),
                            .blob => try query.bindBlob(idx, value),
                            .text => try query.bindText(idx, value),
                        }
                    } else {
                        try query.bindNull(idx);
                    }
                } else {
                    const value = @field(params, binding.name);
                    switch (binding.kind) {
                        .int32 => try query.bindInt32(idx, @intCast(value)),
                        .int64 => try query.bindInt64(idx, @intCast(value)),
                        .float64 => try query.bindFloat64(idx, @floatCast(value)),
                        .blob => try query.bindBlob(idx, value),
                        .text => try query.bindText(idx, value),
                    }
                }
            }
        }

        fn bindNull(query: Self, idx: c_int) !void {
            try errors.throw(c.sqlite3_bind_null(query.ptr, idx));
        }

        fn bindInt32(query: Self, idx: c_int, value: i32) !void {
            try errors.throw(c.sqlite3_bind_int(query.ptr, idx, value));
        }

        fn bindInt64(query: Self, idx: c_int, value: i32) !void {
            try errors.throw(c.sqlite3_bind_int64(query.ptr, idx, value));
        }

        fn bindFloat64(query: Self, idx: c_int, value: f64) !void {
            try errors.throw(c.sqlite3_bind_double(query.ptr, idx, value));
        }

        fn bindBlob(query: Self, idx: c_int, value: []const u8) !void {
            try errors.throw(c.sqlite3_bind_blob64(query.ptr, idx, value.ptr, @intCast(value.len), c.SQLITE_STATIC));
        }

        fn bindText(query: Self, idx: c_int, value: []const u8) !void {
            try errors.throw(c.sqlite3_bind_text64(query.ptr, idx, value.ptr, @intCast(value.len), c.SQLITE_STATIC, c.SQLITE_UTF8));
        }

        fn parse(query: Self) !Result {
            var result: Result = undefined;

            inline for (column_bindings, 0..) |binding, i| {
                const n = query.column_indices[i];
                switch (c.sqlite3_column_type(query.ptr, n)) {
                    c.SQLITE_NULL => if (binding.nullable) {
                        @field(result, binding.name) = null;
                    } else {
                        return error.InvalidColumnType;
                    },

                    c.SQLITE_INTEGER => switch (binding.type) {
                        .int32 => |info| {
                            const value = query.columnInt32(n);
                            switch (info.signedness) {
                                .signed => {},
                                .unsigned => {
                                    if (value < 0) {
                                        return error.IntegerOutOfRange;
                                    }
                                },
                            }

                            @field(result, binding.name) = @intCast(value);
                        },
                        .int64 => |info| {
                            const value = query.columnInt64(n);
                            switch (info.signedness) {
                                .signed => {},
                                .unsigned => {
                                    if (value < 0) {
                                        return error.IntegerOutOfRange;
                                    }
                                },
                            }

                            @field(result, binding.name) = @intCast(value);
                        },
                        else => return error.InvalidColumnType,
                    },

                    c.SQLITE_FLOAT => switch (binding.type) {
                        .float64 => {
                            const value = query.columnFloat64(n);
                            @field(result, binding.name) = @floatCast(value);
                        },
                        else => return error.InvalidColumnType,
                    },

                    c.SQLITE_BLOB => switch (binding.type) {
                        .blob => {
                            const data = query.columnBlob(n);
                            @field(result, binding.name) = types.Blob{ .data = data };
                        },
                        else => return error.InvalidColumnType,
                    },

                    c.SQLITE_TEXT => switch (binding.type) {
                        .text => {
                            const data = query.columnText(n);
                            @field(result, binding.name) = types.Text{ .data = data };
                        },
                        else => return error.InvalidColumnType,
                    },

                    else => @panic("internal SQLite error"),
                }
            }

            return result;
        }

        fn columnInt32(query: Self, n: c_int) i32 {
            return c.sqlite3_column_int(query.ptr, n);
        }

        fn columnInt64(query: Self, n: c_int) i64 {
            return c.sqlite3_column_int64(query.ptr, n);
        }

        fn columnFloat64(query: Self, n: c_int) f64 {
            return c.sqlite3_column_double(query.ptr, n);
        }

        fn columnBlob(query: Self, n: c_int) []const u8 {
            const ptr: [*]const u8 = @intCast(c.sqlite3_column_blob(query.ptr, n));
            const len = c.sqlite3_column_bytes(query.ptr, n);
            return ptr[0..len];
        }

        fn columnText(query: Self, n: c_int) []const u8 {
            const ptr: [*]const u8 = @intCast(c.sqlite3_column_text(query.ptr, n));
            const len = c.sqlite3_column_bytes(query.ptr, n);
            return ptr[0..len];
        }
    };
}
