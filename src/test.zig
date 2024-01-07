const std = @import("std");

const Database = @import("Database.zig");

const Query = @import("Query.zig").Query;
const Method = @import("Method.zig").Method;

test "open and close an in-memory database" {
    const db = try Database.openZ(null, .{});
    try db.close();
}

test "Method" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const db = try Database.openZ(null, .{});
    defer db.close() catch |err| {
        std.log.err("ERROR: {any}", .{err});
    };

    {
        const method = try Method(struct {}).init(db, "CREATE TABLE users(age FLOAT)");
        defer method.deinit();
        try method.exec(.{});
    }

    {
        const method = try Method(struct { age: f32 }).init(db, "INSERT INTO users VALUES (:age)");
        defer method.deinit();
        try method.exec(.{ .age = 5 });
        try method.exec(.{ .age = 7 });
        try method.exec(.{ .age = 9 });
    }

    {
        const Params = struct {};
        const Result = struct { age: f32 };
        const query = try Query(Params, Result).init(db, "SELECT age FROM users");
        defer query.deinit();

        const row = try query.get(.{});
        try std.testing.expectEqual(@as(?Result, .{ .age = 5 }), row);

        var results = std.ArrayList(Result).init(allocator);
        defer results.deinit();

        try query.bind(.{});
        while (try query.step()) |result| try results.append(result);

        try std.testing.expectEqualSlices(
            Result,
            &.{ .{ .age = 5 }, .{ .age = 7 }, .{ .age = 9 } },
            results.items,
        );
    }
}
