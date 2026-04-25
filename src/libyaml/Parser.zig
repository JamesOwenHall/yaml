const std = @import("std");
const clibyaml = @import("clibyaml");
const Event = @import("Event.zig");
const Parser = @This();

inner: clibyaml.yaml_parser_t,

const InitializeError = error{
    InitializeError,
};

const ParseError = error{
    ParseError,
};

pub fn init() InitializeError!Parser {
    var inner: clibyaml.yaml_parser_t = undefined;
    if (clibyaml.yaml_parser_initialize(&inner) == 0) {
        return InitializeError.InitializeError;
    }
    return .{ .inner = inner };
}

pub fn deinit(self: *Parser) void {
    clibyaml.yaml_parser_delete(&self.inner);
}

pub fn set_input_string(self: *Parser, str: []const u8) void {
    clibyaml.yaml_parser_set_input_string(&self.inner, str.ptr, str.len);
}

pub fn set_encoding(self: *Parser, encoding: Event.Encoding) void {
    self.inner.encoding = @intFromEnum(encoding);
}

pub fn parse(self: *Parser) ParseError!Event {
    var raw: clibyaml.yaml_event_t = undefined;
    if (clibyaml.yaml_parser_parse(&self.inner, &raw) == 0) {
        return ParseError.ParseError;
    }

    return Event.init(raw);
}

test "parse StreamStart" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
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

test "parse DocumentStart" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
    defer parser.deinit();

    const input =
        \\foo: faa
        \\...
        \\
        \\%YAML 1.2
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

    try std.testing.expectEqual(2, starts.items.len);

    // Doc 1
    const exp_1 = Event.DocumentStart{
        .version_directive = null,
        .tag_directives = .{ .start = null, .end = null },
        .implicit = true,
    };
    try std.testing.expectEqualDeep(exp_1, starts.items[0]);

    // Doc 2
    try std.testing.expectEqual(Event.VersionDirective{ .major = 1, .minor = 2 }, starts.items[1].version_directive);
    var iter = starts.items[1].tag_directives.iter();
    var list = std.ArrayList(Event.TagDirective).empty;
    defer list.deinit(gpa);
    while (iter.next()) |directive| {
        try list.append(gpa, directive);
    }

    try std.testing.expectEqualDeep(expected, list.items);
}

test "parse DocumentEnd" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
    defer parser.deinit();

    const input =
        \\foo: faa
        \\---
        \\foo: faa
        \\...
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var ends = try filter_events(gpa, events.items, .DocumentEnd, Event.DocumentEnd);
    defer ends.deinit(gpa);

    const expected: []const Event.DocumentEnd = &.{
        .{ .implicit = true },
        .{ .implicit = false },
    };
    try std.testing.expectEqualDeep(expected, ends.items);
}

test "parse Alias" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
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

test "parse Scalar" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
    defer parser.deinit();

    const input =
        \\- &foo 2
        \\- !bar "baz"
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var scalars = try filter_events(gpa, events.items, .Scalar, Event.Scalar);
    defer scalars.deinit(gpa);

    const expected: []const Event.Scalar = &.{
        .{
            .anchor = "foo",
            .style = .Plain,
            .tag = null,
            .value = "2",
        },
        .{
            .anchor = null,
            .style = .DoubleQuoted,
            .tag = "!bar",
            .value = "baz",
        },
    };
    try std.testing.expectEqualDeep(expected, scalars.items);
}

test "parse SequenceStart" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
    defer parser.deinit();

    const input =
        \\foo: !bar &faa
        \\  - baz
        \\foo2: [2]
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var seqs = try filter_events(gpa, events.items, .SequenceStart, Event.SequenceStart);
    defer seqs.deinit(gpa);

    const expected: []const Event.SequenceStart = &.{
        .{ .anchor = "faa", .tag = "!bar", .implicit = false, .style = .Block },
        .{ .anchor = null, .tag = null, .implicit = true, .style = .Flow },
    };

    try std.testing.expectEqualDeep(expected, seqs.items);
}

test "parse MappingStart" {
    const gpa = std.testing.allocator;
    var parser = try Parser.init();
    defer parser.deinit();

    const input =
        \\- foo: faa
        \\- &faa {foo: bar}
        \\- !faa {foo: bar}
    ;
    parser.set_input_string(input);

    var events = try collect_events(gpa, &parser);
    defer deinit_list(gpa, &events);

    var starts = try filter_events(gpa, events.items, .MappingStart, Event.MappingStart);
    defer starts.deinit(gpa);

    const expected: []const Event.MappingStart = &.{
        .{ .anchor = null, .tag = null, .implicit = true, .style = .Block },
        .{ .anchor = "faa", .tag = null, .implicit = true, .style = .Flow },
        .{ .anchor = null, .tag = "!faa", .implicit = false, .style = .Flow },
    };

    try std.testing.expectEqualDeep(expected, starts.items);
}

// === Test helpers ===

fn collect_events(gpa: std.mem.Allocator, parser: *Parser) !std.ArrayList(Event) {
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
