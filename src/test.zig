const std = @import("std");

const c = @import("c.zig");
const errors = @import("errors.zig");
const sqlite = @import("sqlite.zig");

test "open and close an in-memory database" {
    const db = try sqlite.Database.init(.{});
    defer db.deinit();
}

test "insert" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();
    _ = allocator;

    const db = try sqlite.Database.init(.{});
    defer db.deinit();

    try db.exec("CREATE TABLE users(age FLOAT)", .{});
    const User = struct { age: f32 };

    {
        const insert = try db.prepare(User, void, "INSERT INTO users VALUES (:age)");
        defer insert.deinit();

        try insert.exec(.{ .age = 5 });
        try insert.exec(.{ .age = 7 });
        try insert.exec(.{ .age = 9 });
    }

    {
        const select = try db.prepare(struct {}, User, "SELECT age FROM users");
        defer select.deinit();

        try select.bind(.{});
        defer select.reset();
        try std.testing.expectEqual(@as(?User, .{ .age = 5 }), try select.step());
        try std.testing.expectEqual(@as(?User, .{ .age = 7 }), try select.step());
        try std.testing.expectEqual(@as(?User, .{ .age = 9 }), try select.step());
        try std.testing.expectEqual(@as(?User, null), try select.step());
    }
}
