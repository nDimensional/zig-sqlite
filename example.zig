const std = @import("std");

pub fn main() !void {
    const Options = packed struct {
        opt1: bool,
        opt2: bool,
        opt3: bool,
        opt4: bool,
        opt5: bool,
        opt6: bool,
        opt7: bool,
        opt8: bool,

        opt9: bool,
    };

    std.log.info("options size: {d}", .{@sizeOf(Options)});

    switch (@typeInfo(Options)) {
        .@"struct" => |info| std.log.info("options info: {any}", .{info.backing_integer}),
        else => {},
    }
}
