//! This module runs basic sanity checks against the LibYAML C library to ensure it builds correctly.
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

test "parse string" {
    const gpa = std.testing.allocator;
    const input =
        \\foo:
        \\  bar: baz
        \\  jib: jab
    ;

    var parser: libyaml.yaml_parser_t = undefined;
    std.debug.assert(libyaml.yaml_parser_initialize(&parser) == 1);
    defer libyaml.yaml_parser_delete(&parser);

    libyaml.yaml_parser_set_input_string(&parser, input, input.len);

    var event_types = std.ArrayList(libyaml.yaml_event_type_t).empty;
    defer event_types.deinit(gpa);

    while (true) {
        var event: libyaml.yaml_event_t = undefined;
        if (libyaml.yaml_parser_parse(&parser, &event) != 1) {
            return error.ParseError;
        }
        defer libyaml.yaml_event_delete(&event);

        try event_types.append(gpa, event.type);
        if (event.type == libyaml.YAML_STREAM_END_EVENT) {
            break;
        }
    }

    const expected = [_]libyaml.yaml_event_type_t{
        libyaml.YAML_STREAM_START_EVENT,
        libyaml.YAML_DOCUMENT_START_EVENT,
        libyaml.YAML_MAPPING_START_EVENT,
        libyaml.YAML_SCALAR_EVENT,
        libyaml.YAML_MAPPING_START_EVENT,
        libyaml.YAML_SCALAR_EVENT,
        libyaml.YAML_SCALAR_EVENT,
        libyaml.YAML_SCALAR_EVENT,
        libyaml.YAML_SCALAR_EVENT,
        libyaml.YAML_MAPPING_END_EVENT,
        libyaml.YAML_MAPPING_END_EVENT,
        libyaml.YAML_DOCUMENT_END_EVENT,
        libyaml.YAML_STREAM_END_EVENT,
    };

    try std.testing.expectEqualSlices(libyaml.yaml_event_type_t, &expected, event_types.items);
}
