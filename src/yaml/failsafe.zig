const std = @import("std");

pub const Schema = @import("failsafe/Schema.zig");

test "all" {
    std.testing.refAllDecls(@This());
}
