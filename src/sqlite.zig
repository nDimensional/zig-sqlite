const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");

pub const Error = errors.Error;
pub const Blob = struct { data: []const u8 };
pub const Text = struct { data: []const u8 };

pub fn blob(data: []const u8) Blob {
    return .{ .data = data };
}

pub fn text(data: []const u8) Text {
    return .{ .data = data };
}

pub const Database = struct {
    pub const Mode = enum { ReadWrite, ReadOnly };

    pub const Options = struct {
        path: ?[*:0]const u8 = null,
        mode: Mode = .ReadWrite,
        create: bool = true,
    };

    ptr: ?*c.sqlite3,

    pub fn open(options: Options) !Database {
        var ptr: ?*c.sqlite3 = null;

        var flags: c_int = 0;
        switch (options.mode) {
            .ReadOnly => {
                flags |= c.SQLITE_OPEN_READONLY;
            },
            .ReadWrite => {
                flags |= c.SQLITE_OPEN_READWRITE;
                if (options.create and options.path != null) {
                    flags |= c.SQLITE_OPEN_CREATE;
                }
            },
        }

        try errors.throw(c.sqlite3_open_v2(options.path, &ptr, flags, null));

        return .{ .ptr = ptr };
    }

    /// Must not be in WAL mode. Returns a read-only in-memory database.
    pub fn import(data: []const u8) !Database {
        const db = try Database.open(.{ .mode = .ReadOnly });
        const ptr: [*]u8 = @constCast(data.ptr);
        const len: c_longlong = @intCast(data.len);
        const flags = c.SQLITE_DESERIALIZE_READONLY;
        try errors.throw(c.sqlite3_deserialize(db.ptr, "main", ptr, len, len, flags));
        return db;
    }

    pub fn close(db: Database) void {
        errors.throw(c.sqlite3_close_v2(db.ptr)) catch |err| {
            const msg = c.sqlite3_errmsg(db.ptr);
            std.debug.panic("sqlite3_close_v2: {s} {s}", .{ @errorName(err), msg });
        };
    }

    pub fn prepare(db: Database, comptime Params: type, comptime Result: type, sql: []const u8) !Statement(Params, Result) {
        return try Statement(Params, Result).prepare(db, sql);
    }

    pub fn exec(db: Database, sql: []const u8, params: anytype) !void {
        const stmt = try Statement(@TypeOf(params), void).prepare(db, sql);
        defer stmt.finalize();

        try stmt.exec(params);
    }
};

pub fn Statement(comptime Params: type, comptime Result: type) type {
    const param_bindings = switch (@typeInfo(Params)) {
        .Struct => |info| Binding.parseStruct(info),
        else => @compileError("Params type must be a struct"),
    };

    const column_bindings = switch (@typeInfo(Result)) {
        .Void => .{},
        .Struct => |info| Binding.parseStruct(info),
        else => @compileError("Result type must be a struct or void"),
    };

    const param_count = param_bindings.len;
    const column_count = column_bindings.len;
    const placeholder: c_int = -1;

    return struct {
        const Self = @This();

        ptr: ?*c.sqlite3_stmt = null,
        param_index_map: [param_count]c_int = .{placeholder} ** param_count,
        column_index_map: [column_count]c_int = .{placeholder} ** column_count,

        pub fn prepare(db: Database, sql: []const u8) !Self {
            var stmt = Self{};

            try errors.throw(c.sqlite3_prepare_v2(db.ptr, sql.ptr, @intCast(sql.len), &stmt.ptr, null));
            errdefer errors.throw(c.sqlite3_finalize(stmt.ptr)) catch |err| {
                const msg = c.sqlite3_errmsg(db.ptr);
                std.debug.panic("sqlite3_finalize: {s} {s}", .{ @errorName(err), msg });
            };

            // Populate stmt.param_index_map
            {
                const count = c.sqlite3_bind_parameter_count(stmt.ptr);

                var idx: c_int = 1;
                params: while (idx <= count) : (idx += 1) {
                    const parameter_name = c.sqlite3_bind_parameter_name(stmt.ptr, idx);
                    if (parameter_name == null) {
                        return error.InvalidParameter;
                    }

                    const name = std.mem.span(parameter_name);
                    if (name.len == 0) {
                        return error.InvalidParameter;
                    } else switch (name[0]) {
                        ':', '$', '@' => {},
                        else => return error.InvalidParameter,
                    }

                    inline for (param_bindings, 0..) |binding, i| {
                        if (std.mem.eql(u8, binding.name, name[1..])) {
                            if (stmt.param_index_map[i] == placeholder) {
                                stmt.param_index_map[i] = idx;
                                continue :params;
                            } else {
                                return error.DuplicateParameter;
                            }
                        }
                    }

                    return error.MissingParameter;
                }
            }

            // Populate stmt.column_index_map
            {
                const count = c.sqlite3_column_count(stmt.ptr);

                var n: c_int = 0;
                columns: while (n < count) : (n += 1) {
                    const column_name = c.sqlite3_column_name(stmt.ptr, n);
                    if (column_name == null) {
                        return error.OutOfMemory;
                    }

                    const name = std.mem.span(column_name);

                    inline for (column_bindings, 0..) |binding, i| {
                        if (std.mem.eql(u8, binding.name, name)) {
                            if (stmt.column_index_map[i] == placeholder) {
                                stmt.column_index_map[i] = n;
                                continue :columns;
                            } else {
                                return error.DuplicateColumn;
                            }
                        }
                    }
                }

                for (stmt.column_index_map) |i| {
                    if (i == placeholder) {
                        return error.MissingColumn;
                    }
                }
            }

            return stmt;
        }

        pub fn finalize(stmt: Self) void {
            errors.throw(c.sqlite3_finalize(stmt.ptr)) catch |err| {
                const db = c.sqlite3_db_handle(stmt.ptr);
                const msg = c.sqlite3_errmsg(db);
                std.debug.panic("sqlite3_finalize: {s} {s}", .{ @errorName(err), msg });
            };
        }

        pub fn reset(stmt: Self) void {
            errors.throw(c.sqlite3_reset(stmt.ptr)) catch |err| {
                const msg = c.sqlite3_errmsg(c.sqlite3_db_handle(stmt.ptr));
                std.debug.panic("sqlite3_reset: {s} {s}", .{ @errorName(err), msg });
            };

            errors.throw(c.sqlite3_clear_bindings(stmt.ptr)) catch |err| {
                const msg = c.sqlite3_errmsg(c.sqlite3_db_handle(stmt.ptr));
                std.debug.panic("sqlite3_clear_bindings: {s} {s}", .{ @errorName(err), msg });
            };
        }

        pub fn exec(stmt: Self, params: Params) !void {
            switch (@typeInfo(Result)) {
                .Void => {},
                else => @compileError("only void Result types can call .exec"),
            }

            try stmt.bind(params);
            defer stmt.reset();
            try stmt.step() orelse {};
        }

        pub fn step(stmt: Self) !?Result {
            switch (c.sqlite3_step(stmt.ptr)) {
                c.SQLITE_ROW => return try stmt.row(),
                c.SQLITE_DONE => return null,
                else => |code| {
                    // sqlite3_reset returns the same code we already have
                    const rc = c.sqlite3_reset(stmt.ptr);
                    if (rc == code) {
                        return errors.getError(code);
                    } else {
                        const err = errors.getError(rc);
                        const msg = c.sqlite3_errmsg(c.sqlite3_db_handle(stmt.ptr));
                        std.debug.panic("sqlite3_reset: {s} {s}", .{ @errorName(err), msg });
                    }
                },
            }
        }

        pub fn bind(stmt: Self, params: Params) !void {
            inline for (param_bindings, 0..) |binding, i| {
                const idx = stmt.param_index_map[i];
                if (binding.nullable) {
                    if (@field(params, binding.name)) |value| {
                        switch (binding.type) {
                            .int32 => try stmt.bindInt32(idx, @intCast(value)),
                            .int64 => try stmt.bindInt64(idx, @intCast(value)),
                            .float64 => try stmt.bindFloat64(idx, @floatCast(value)),
                            .blob => try stmt.bindBlob(idx, value),
                            .text => try stmt.bindText(idx, value),
                        }
                    } else {
                        try stmt.bindNull(idx);
                    }
                } else {
                    const value = @field(params, binding.name);
                    switch (binding.type) {
                        .int32 => try stmt.bindInt32(idx, @intCast(value)),
                        .int64 => try stmt.bindInt64(idx, @intCast(value)),
                        .float64 => try stmt.bindFloat64(idx, @floatCast(value)),
                        .blob => try stmt.bindBlob(idx, value),
                        .text => try stmt.bindText(idx, value),
                    }
                }
            }
        }

        fn bindNull(stmt: Self, idx: c_int) !void {
            try errors.throw(c.sqlite3_bind_null(stmt.ptr, idx));
        }

        fn bindInt32(stmt: Self, idx: c_int, value: i32) !void {
            try errors.throw(c.sqlite3_bind_int(stmt.ptr, idx, value));
        }

        fn bindInt64(stmt: Self, idx: c_int, value: i64) !void {
            try errors.throw(c.sqlite3_bind_int64(stmt.ptr, idx, value));
        }

        fn bindFloat64(stmt: Self, idx: c_int, value: f64) !void {
            try errors.throw(c.sqlite3_bind_double(stmt.ptr, idx, value));
        }

        fn bindBlob(stmt: Self, idx: c_int, value: Blob) !void {
            const ptr = value.data.ptr;
            const len = value.data.len;
            try errors.throw(c.sqlite3_bind_blob64(stmt.ptr, idx, ptr, @intCast(len), c.SQLITE_STATIC));
        }

        fn bindText(stmt: Self, idx: c_int, value: Text) !void {
            const ptr = value.data.ptr;
            const len = value.data.len;
            try errors.throw(c.sqlite3_bind_text64(stmt.ptr, idx, ptr, @intCast(len), c.SQLITE_STATIC, c.SQLITE_UTF8));
        }

        fn row(stmt: Self) !Result {
            var result: Result = undefined;

            inline for (column_bindings, 0..) |binding, i| {
                const n = stmt.column_index_map[i];

                switch (c.sqlite3_column_type(stmt.ptr, n)) {
                    c.SQLITE_NULL => if (binding.nullable) {
                        @field(result, binding.name) = null;
                    } else {
                        return error.InvalidColumnType;
                    },

                    c.SQLITE_INTEGER => switch (binding.type) {
                        .int32 => |info| {
                            const value = stmt.columnInt32(n);
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
                            const value = stmt.columnInt64(n);
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
                        .float64 => @field(result, binding.name) = @floatCast(stmt.columnFloat64(n)),
                        else => return error.InvalidColumnType,
                    },

                    c.SQLITE_BLOB => switch (binding.type) {
                        .blob => @field(result, binding.name) = stmt.columnBlob(n),
                        else => return error.InvalidColumnType,
                    },

                    c.SQLITE_TEXT => switch (binding.type) {
                        .text => @field(result, binding.name) = stmt.columnText(n),
                        else => return error.InvalidColumnType,
                    },

                    else => @panic("internal SQLite error"),
                }
            }

            return result;
        }

        fn columnInt32(stmt: Self, n: c_int) i32 {
            return c.sqlite3_column_int(stmt.ptr, n);
        }

        fn columnInt64(stmt: Self, n: c_int) i64 {
            return c.sqlite3_column_int64(stmt.ptr, n);
        }

        fn columnFloat64(stmt: Self, n: c_int) f64 {
            return c.sqlite3_column_double(stmt.ptr, n);
        }

        fn columnBlob(stmt: Self, n: c_int) Blob {
            const ptr: [*]const u8 = @ptrCast(c.sqlite3_column_blob(stmt.ptr, n));
            const len = c.sqlite3_column_bytes(stmt.ptr, n);
            if (len < 0) {
                std.debug.panic("sqlite3_column_bytes: len < 0", .{});
            }

            return blob(ptr[0..@intCast(len)]);
        }

        fn columnText(stmt: Self, n: c_int) Text {
            const ptr: [*]const u8 = @ptrCast(c.sqlite3_column_text(stmt.ptr, n));
            const len = c.sqlite3_column_bytes(stmt.ptr, n);
            if (len < 0) {
                std.debug.panic("sqlite3_column_bytes: len < 0", .{});
            }

            return text(ptr[0..@intCast(len)]);
        }
    };
}

const Binding = struct {
    pub const TypeTag = enum {
        int32,
        int64,
        float64,
        blob,
        text,
    };

    pub const Type = union(TypeTag) {
        int32: std.builtin.Type.Int,
        int64: std.builtin.Type.Int,
        float64: std.builtin.Type.Float,
        blob: void,
        text: void,

        pub fn parse(comptime T: type) Type {
            return switch (T) {
                Blob => .{ .blob = {} },
                Text => .{ .text = {} },
                else => switch (@typeInfo(T)) {
                    .Int => |info| switch (info.signedness) {
                        .signed => if (info.bits <= 32) .{ .int32 = info } else .{ .int64 = info },
                        .unsigned => if (info.bits <= 31) .{ .int32 = info } else .{ .int64 = info },
                    },
                    .Float => |info| .{ .float64 = info },
                    else => @compileError("invalid binding type"),
                },
            };
        }
    };

    pub const Kind = enum {
        int32,
        int64,
        float64,
        blob,
        text,

        pub fn parse(comptime T: type) Kind {
            return switch (T) {
                Blob => .blob,
                Text => .text,
                else => switch (@typeInfo(T)) {
                    .Int => |info| switch (info.signedness) {
                        .signed => if (info.bits <= 32) .int32 else .int64,
                        .unsigned => if (info.bits <= 31) .int32 else .int64,
                    },
                    .Float => .float64,
                    else => @compileError("invalid binding type"),
                },
            };
        }
    };

    name: []const u8,
    type: Type,
    nullable: bool,

    pub fn parseStruct(comptime info: std.builtin.Type.Struct) [info.fields.len]Binding {
        var bindings: [info.fields.len]Binding = undefined;
        inline for (info.fields, 0..) |field, i| {
            bindings[i] = parseField(field);
        }

        return bindings;
    }

    pub fn parseField(comptime field: std.builtin.Type.StructField) Binding {
        return switch (@typeInfo(field.type)) {
            .Optional => |field_type| Binding{
                .name = field.name,
                .type = Type.parse(field_type.child),
                .nullable = true,
            },
            else => Binding{
                .name = field.name,
                .type = Type.parse(field.type),
                .nullable = false,
            },
        };
    }
};
