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

pub fn set_encoding(self: *@This(), encoding: Event.Encoding) void {
    self.inner.encoding = @intFromEnum(encoding);
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
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);
    parser.set_encoding(.Utf8);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .StreamStart, Event.StreamStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);
    try std.testing.expectEqual(Event.Encoding.Utf8, starts.items[0].encoding);
}

// === DocumentStart ===

test "parse DocumentStart no version directive" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .DocumentStart, Event.DocumentStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);
    try std.testing.expectEqual(null, starts.items[0].version_directive);
}

test "parse DocumentStart with valid version directive" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\%YAML 1.2
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .DocumentStart, Event.DocumentStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);
    try std.testing.expectEqual(starts.items[0].version_directive, Event.VersionDirective{
        .major = 1,
        .minor = 2,
    });
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
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .DocumentStart, Event.DocumentStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);
    var iter = starts.items[0].tag_directives.iter();
    try std.testing.expectEqual(null, iter.next());
}

test "parse DocumentStart with tag directives" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\%TAG ! tag:clarkevans.com,2002:
        \\%TAG !other! tag:example.org:
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    const expected = &[_]Event.TagDirective{
        .{ .handle = "!", .prefix = "tag:clarkevans.com,2002:" },
        .{ .handle = "!other!", .prefix = "tag:example.org:" },
    };

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .DocumentStart, Event.DocumentStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);

    var iter = starts.items[0].tag_directives.iter();
    var list = std.ArrayList(Event.TagDirective).empty;
    defer list.deinit(gpa);
    while (iter.next()) |directive| {
        try list.append(gpa, directive);
    }

    try std.testing.expectEqualDeep(expected, list.items);
}

test "parse DocumentStart with implicit start" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .DocumentStart, Event.DocumentStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);
    try std.testing.expect(starts.items[0].implicit);
}

test "parse DocumentStart with explicit start" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\---
        \\foo: faa
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .DocumentStart, Event.DocumentStart);
    defer starts.deinit(gpa);

    try std.testing.expectEqual(1, starts.items.len);
    try std.testing.expect(!starts.items[0].implicit);
}

// === DocumentEnd ===

test "parse DocumentEnd with implicit" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var ends = try filter_events(gpa, events.items, .DocumentEnd, Event.DocumentEnd);
    defer ends.deinit(gpa);

    try std.testing.expectEqual(1, ends.items.len);
    try std.testing.expect(ends.items[0].implicit);
}

test "parse DocumentEnd with explicit" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: faa
        \\...
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var ends = try filter_events(gpa, events.items, .DocumentEnd, Event.DocumentEnd);
    defer ends.deinit(gpa);

    try std.testing.expectEqual(1, ends.items.len);
    try std.testing.expect(!ends.items[0].implicit);
}

test "parse Alias" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: &foo bar
        \\baz: *foo
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var aliases = try filter_events(gpa, events.items, .Alias, Event.Alias);
    defer aliases.deinit(gpa);

    try std.testing.expectEqual(1, aliases.items.len);
    try std.testing.expectEqualStrings("foo", aliases.items[0].anchor);
}

// === SequenceStart ===

test "parse SequenceStart anchor" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: &foo
        \\  - bar
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var seqs = try filter_events(gpa, events.items, Event.Type.SequenceStart, Event.SequenceStart);
    defer seqs.deinit(gpa);

    try std.testing.expectEqual(1, seqs.items.len);
    try std.testing.expectEqualStrings("foo", seqs.items[0].anchor.?);
}

test "parse SequenceStart tag" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: !bar []
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var seqs = try filter_events(gpa, events.items, .SequenceStart, Event.SequenceStart);
    defer seqs.deinit(gpa);

    try std.testing.expectEqual(1, seqs.items.len);
    try std.testing.expectEqualStrings("!bar", seqs.items[0].tag.?);
    // `implicit` just means there's no explicit tag.
    try std.testing.expect(!seqs.items[0].implicit);
}

test "parse SequenceStart implicit" {
    const gpa = std.testing.allocator;
    var parser = try @This().init();
    defer parser.deinit();

    const input =
        \\foo: []
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var seqs = try filter_events(gpa, events.items, .SequenceStart, Event.SequenceStart);
    defer seqs.deinit(gpa);

    try std.testing.expectEqual(1, seqs.items.len);
    try std.testing.expectEqual(null, seqs.items[0].tag);
    try std.testing.expect(seqs.items[0].implicit);
}

// === Test helpers ===

fn collect_events(gpa: std.mem.Allocator, parser: *@This()) !std.ArrayList(Event) {
    var list = std.ArrayList(Event).empty;
    errdefer deinit_list(gpa, &list);

    while (true) {
        const event = try parser.parse();
        try list.append(gpa, event);

        if (event.data == Event.Type.None) {
            break;
        }
    }

    return list;
}

fn deinit_list(gpa: std.mem.Allocator, list: *std.ArrayList(Event)) void {
    for (list.items) |*event| {
        event.deinit();
    }

    list.deinit(gpa);
}

fn filter_events(gpa: std.mem.Allocator, events: []Event, comptime event_type: Event.Type, result: type) !std.ArrayList(result) {
    var list = std.ArrayList(result).empty;
    errdefer list.deinit(gpa);

    for (events) |event| {
        switch (event.data) {
            event_type => |res| {
                try list.append(gpa, res);
            },
            else => {},
        }
    }

    return list;
}
