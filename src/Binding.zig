const std = @import("std");
const c = @import("c.zig");
const errors = @import("errors.zig");
const types = @import("types.zig");

const Database = @import("Database.zig");

const Binding = @This();

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
            types.Blob => .{ .blob = {} },
            types.Text => .{ .text = {} },
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
            types.Blob => .blob,
            types.Text => .text,
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

pub fn parseFields(comptime fields: []const std.builtin.Type.StructField) [fields.len]Binding {
    var bindings: [fields.len]Binding = undefined;
    inline for (fields, 0..) |field, i| {
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
