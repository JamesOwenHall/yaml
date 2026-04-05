const std = @import("std");
const libyaml = @import("libyaml");

test "get_version_string" {
    const actual = std.mem.span(libyaml.yaml_get_version_string());
    try std.testing.expectEqualStrings("0.2.5", actual);
}

test "get_version" {
    var major: c_int = undefined;
    var minor: c_int = undefined;
    var patch: c_int = undefined;

    libyaml.yaml_get_version(&major, &minor, &patch);

    try std.testing.expectEqual(0, major);
    try std.testing.expectEqual(2, minor);
    try std.testing.expectEqual(5, patch);
}
