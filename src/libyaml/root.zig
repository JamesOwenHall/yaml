const std = @import("std");
const clibyaml = @import("clibyaml");

pub const Event = @import("Event.zig");
pub const Parser = @import("Parser.zig");

pub const Version = struct {
    major: i32,
    minor: i32,
    patch: i32,
};

pub fn get_version() Version {
    var version: Version = undefined;
    clibyaml.yaml_get_version(&version.major, &version.minor, &version.patch);

    return version;
}

pub fn get_version_string() []const u8 {
    return std.mem.span(clibyaml.yaml_get_version_string());
}

test {
    std.testing.refAllDecls(@This());
}

test "get_version" {
    const expected = Version{ .major = 0, .minor = 2, .patch = 5 };
    try std.testing.expectEqual(expected, get_version());
}

test "get_version_string" {
    try std.testing.expectEqual("0.2.5", get_version_string());
}
