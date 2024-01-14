const std = @import("std");

const c = @import("c.zig");
const errors = @import("errors.zig");
const sqlite = @import("sqlite.zig");

test "open and close an in-memory database" {
    const db = try sqlite.Database.init(.{});
    defer db.deinit();
}

test "insert" {
    const db = try sqlite.Database.init(.{});
    defer db.deinit();

    try db.exec("CREATE TABLE users(id TEXT PRIMARY KEY, age FLOAT)", .{});
    const User = struct { id: sqlite.Text, age: ?f32 };

    {
        const insert = try db.prepare(User, void, "INSERT INTO users VALUES (:id, :age)");
        defer insert.deinit();

        try insert.exec(.{ .id = sqlite.text("a"), .age = 5 });
        try insert.exec(.{ .id = sqlite.text("b"), .age = 7 });
        try insert.exec(.{ .id = sqlite.text("c"), .age = null });
    }

    {
        const select = try db.prepare(struct {}, User, "SELECT id, age FROM users");
        defer select.deinit();

        try select.bind(.{});
        defer select.reset();

        if (try select.step()) |user| {
            try std.testing.expectEqualSlices(u8, "a", user.id.data);
            try std.testing.expectEqual(@as(?f32, 5), user.age);
        } else try std.testing.expect(false);

        if (try select.step()) |user| {
            try std.testing.expectEqualSlices(u8, "b", user.id.data);
            try std.testing.expectEqual(@as(?f32, 7), user.age);
        } else try std.testing.expect(false);

        if (try select.step()) |user| {
            try std.testing.expectEqualSlices(u8, "c", user.id.data);
            try std.testing.expectEqual(@as(?f32, null), user.age);
        } else try std.testing.expect(false);

        try std.testing.expectEqual(@as(?User, null), try select.step());
    }
}

test "count" {
    const db = try sqlite.Database.init(.{});
    defer db.deinit();

    try db.exec("CREATE TABLE users(id TEXT PRIMARY KEY, age FLOAT)", .{});
    try db.exec("INSERT INTO users VALUES(\"a\", 21)", .{});
    try db.exec("INSERT INTO users VALUES(\"b\", 23)", .{});
    try db.exec("INSERT INTO users VALUES(\"c\", NULL)", .{});

    {
        const Result = struct { age: f32 };
        const select = try db.prepare(struct {}, Result, "SELECT age FROM users");
        defer select.deinit();

        try select.bind(.{});
        defer select.reset();

        try std.testing.expectEqual(@as(?Result, .{ .age = 21 }), try select.step());
    }

    {
        const Result = struct { count: usize };
        const select = try db.prepare(struct {}, Result, "SELECT count(*) as count FROM users");
        defer select.deinit();

        try select.bind(.{});
        defer select.reset();

        try std.testing.expectEqual(@as(?Result, .{ .count = 3 }), try select.step());
    }
}
