const std = @import("std");
const clibyaml = @import("clibyaml");
const Event = @import("Event.zig");

const InitializeError = error{
    InitializeError,
};

const ParseError = error{
    ParseError,
};

inner: clibyaml.yaml_parser_t,

pub fn init() InitializeError!@This() {
    var inner: clibyaml.yaml_parser_t = undefined;
    if (clibyaml.yaml_parser_initialize(&inner) == 0) {
        return InitializeError.InitializeError;
    }
    return .{ .inner = inner };
}

pub fn deinit(self: *@This()) void {
    clibyaml.yaml_parser_delete(&self.inner);
}

pub fn set_input_string(self: *@This(), str: []const u8) void {
    clibyaml.yaml_parser_set_input_string(&self.inner, str.ptr, str.len);
}

pub fn parse(self: *@This()) ParseError!Event {
    var event: Event = undefined;
    if (clibyaml.yaml_parser_parse(&self.inner, &event.inner) == 0) {
        return ParseError.ParseError;
    }

    event.init();
    return event;
}

// === StreamStart ===

test "parse StreamStart" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .StreamStart => |start| {
                try std.testing.expectEqual(start.encoding, Event.Encoding.Utf8);
            },
            .None => break,
            else => {},
        }
    }
}

// === DocumentStart ===

test "parse DocumentStart no version directive" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentStart => |doc| {
                try std.testing.expectEqual(doc.version_directive, null);
            },
            .None => break,
            else => {},
        }
    }
}

test "parse DocumentStart with valid version directive" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\%YAML 1.2
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentStart => |doc| {
                try std.testing.expectEqual(doc.version_directive, Event.VersionDirective{
                    .major = 1,
                    .minor = 2,
                });
            },
            .None => break,
            else => {},
        }
    }
}

test "parse DocumentStart with invalid version directive" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\%YAML 0.5
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    var stream_event = try parser.parse();
    defer stream_event.deinit();
    try std.testing.expect(stream_event.data == .StreamStart);

    const document_start = parser.parse();
    try std.testing.expectError(ParseError.ParseError, document_start);
}

test "parse DocumentStart with no tag directives" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentStart => |doc| {
                var count: u64 = 0;
                var iter = doc.tag_directives.iter();
                while (iter.next()) |_| {
                    count += 1;
                }

                try std.testing.expectEqual(0, count);
            },
            .None => break,
            else => {},
        }
    }
}

test "parse DocumentStart with tag directives" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\%TAG ! tag:clarkevans.com,2002:
        \\%TAG !other! tag:example.org:
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    const expected = [_]Event.TagDirective{
        .{ .handle = "!", .prefix = "tag:clarkevans.com,2002:" },
        .{ .handle = "!other!", .prefix = "tag:example.org:" },
    };

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentStart => |doc| {
                var count: u64 = 0;
                var iter = doc.tag_directives.iter();
                while (iter.next()) |directive| {
                    try std.testing.expectEqualDeep(expected[count], directive);
                    count += 1;
                }
            },
            .None => break,
            else => {},
        }
    }
}

test "parse DocumentStart with implicit start" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentStart => |doc| {
                try std.testing.expect(doc.implicit);
            },
            .None => break,
            else => {},
        }
    }
}

test "parse DocumentStart with explicit start" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentStart => |doc| {
                try std.testing.expect(!doc.implicit);
            },
            .None => break,
            else => {},
        }
    }
}

// === DocumentEnd ===

test "parse DocumentEnd with implicit" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentEnd => |doc| {
                try std.testing.expect(doc.implicit);
            },
            .None => break,
            else => {},
        }
    }
}

test "parse DocumentEnd with explicit" {
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
        \\...
    ;
    parser.set_input_string(input);

    while (true) {
        var event = try parser.parse();
        defer event.deinit();

        switch (event.data) {
            .DocumentEnd => |doc| {
                try std.testing.expect(!doc.implicit);
            },
            .None => break,
            else => {},
        }
    }
}
