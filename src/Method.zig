const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");
const types = @import("types.zig");

const Database = @import("Database.zig");
const Binding = @import("Binding.zig");

pub fn Method(comptime Params: type) type {
    const param_bindings = switch (@typeInfo(Params)) {
        .Struct => |info| Binding.parseFields(info.fields),
        else => @compileError("Params must be a struct"),
    };

    return struct {
        const Self = @This();

        ptr: ?*c.sqlite3_stmt = null,
        param_indices: [param_bindings.len]c_int = .{0} ** param_bindings.len,

        pub fn init(db: Database, sql: []const u8) !Self {
            var method = Self{};
            try errors.throw(c.sqlite3_prepare_v2(db.ptr, sql.ptr, @intCast(sql.len), &method.ptr, null));
            errdefer _ = c.sqlite3_finalize(method.ptr);

            try method.initParams();
            try method.initColumns();
            return method;
        }

        fn initParams(method: *Self) !void {
            const param_count = c.sqlite3_bind_parameter_count(method.ptr);

            var idx: c_int = 1;
            params: while (idx <= param_count) : (idx += 1) {
                const name = c.sqlite3_bind_parameter_name(method.ptr, idx);
                if (name == null) {
                    return error.UnsupportedBinding;
                }

                const field_name = std.mem.span(name);
                if (field_name.len == 0) {
                    return error.UnsupportedBinding;
                } else switch (field_name[0]) {
                    ':', '$', '@' => {},
                    else => return error.UnsupportedBinding,
                }

                inline for (param_bindings, 0..) |binding, i| {
                    if (std.mem.eql(u8, binding.name, field_name[1..])) {
                        if (method.param_indices[i] == 0) {
                            method.param_indices[i] = idx;
                            continue :params;
                        } else {
                            return error.DuplicateParameter;
                        }
                    }
                }

                return error.InvalidParameter;
            }

            for (method.param_indices) |index| {
                if (index == 0) {
                    return error.MissingParameter;
                }
            }
        }

        fn initColumns(method: *Self) !void {
            const column_count = c.sqlite3_column_count(method.ptr);
            if (column_count > 0) {
                return error.UnexpectedResult;
            }
        }

        pub fn deinit(method: Self) void {
            switch (c.sqlite3_finalize(method.ptr)) {
                c.SQLITE_OK => {},
                else => |code| @panic(@errorName(errors.getError(code))),
            }
        }

        pub fn exec(method: Self, params: Params) !void {
            try errors.throw(c.sqlite3_reset(method.ptr));
            try errors.throw(c.sqlite3_clear_bindings(method.ptr));

            try method.bind(params);

            return switch (c.sqlite3_step(method.ptr)) {
                c.SQLITE_DONE => {},
                c.SQLITE_ROW => error.UnexpectedResult,
                else => |code| errors.getError(code),
            };
        }

        fn bind(method: Self, params: Params) !void {
            inline for (param_bindings, 0..) |binding, i| {
                const idx = method.param_indices[i];
                if (binding.nullable) {
                    if (@field(params, binding.name)) |value| {
                        switch (binding.type) {
                            .int32 => try method.bindInt32(idx, @intCast(value)),
                            .int64 => try method.bindInt64(idx, @intCast(value)),
                            .float64 => try method.bindFloat64(idx, @floatCast(value)),
                            .blob => try method.bindBlob(idx, value),
                            .text => try method.bindText(idx, value),
                        }
                    } else {
                        try method.bindNull(idx);
                    }
                } else {
                    const value = @field(params, binding.name);
                    switch (binding.type) {
                        .int32 => try method.bindInt32(idx, @intCast(value)),
                        .int64 => try method.bindInt64(idx, @intCast(value)),
                        .float64 => try method.bindFloat64(idx, @floatCast(value)),
                        .blob => try method.bindBlob(idx, value),
                        .text => try method.bindText(idx, value),
                    }
                }
            }
        }

        fn bindNull(method: Self, idx: c_int) !void {
            try errors.throw(c.sqlite3_bind_null(method.ptr, idx));
        }

        fn bindInt32(method: Self, idx: c_int, value: i32) !void {
            try errors.throw(c.sqlite3_bind_int(method.ptr, idx, value));
        }

        fn bindInt64(method: Self, idx: c_int, value: i32) !void {
            try errors.throw(c.sqlite3_bind_int64(method.ptr, idx, value));
        }

        fn bindFloat64(method: Self, idx: c_int, value: f64) !void {
            try errors.throw(c.sqlite3_bind_double(method.ptr, idx, value));
        }

        fn bindBlob(method: Self, idx: c_int, value: []const u8) !void {
            try errors.throw(c.sqlite3_bind_blob64(method.ptr, idx, value.ptr, @intCast(value.len), c.SQLITE_STATIC));
        }

        fn bindText(method: Self, idx: c_int, value: []const u8) !void {
            try errors.throw(c.sqlite3_bind_text64(method.ptr, idx, value.ptr, @intCast(value.len), c.SQLITE_STATIC, c.SQLITE_UTF8));
        }
    };
}
