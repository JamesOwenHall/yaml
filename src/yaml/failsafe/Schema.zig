const std = @import("std");
const clibyaml = @import("clibyaml");
const Error = @import("../error.zig").Error;
const EventIterator = @import("../EventIterator.zig");
const Value = @import("value.zig").Value;
const Self = @This();

iter: EventIterator,

pub fn init() !Self {
    const iter: EventIterator = try EventIterator.init();
    return .{ .iter = iter };
}

pub fn deinit(self: *Self) void {
    self.iter.deinit();
}

pub fn set_input_string(self: *Self, input: []const u8) void {
    self.iter.set_input_string(input);
}

pub fn parse(self: *Self, gpa: std.mem.Allocator) Error!Value {
    var next = try self.iter.peek() orelse return Error.ParseError;
    if (next.type == clibyaml.YAML_STREAM_START_EVENT) {
        try self.iter.skip();
        next = try self.iter.peek() orelse return Error.ParseError;
    }
    if (next.type == clibyaml.YAML_DOCUMENT_START_EVENT) {
        try self.iter.skip();
    }

    return self.parse_value(gpa);
}

fn parse_value(self: *Self, gpa: std.mem.Allocator) Error!Value {
    var next = try self.iter.next() orelse return Error.ParseError;
    defer next.deinit();

    return sw: switch (next.inner.type) {
        clibyaml.YAML_SCALAR_EVENT => {
            const slice = next.inner.data.scalar.value[0..next.inner.data.scalar.length];
            break :sw Value{ .string = try gpa.dupe(u8, slice) };
        },
        clibyaml.YAML_SEQUENCE_START_EVENT => {
            var list = std.ArrayList(Value).empty;
            errdefer {
                for (list.items) |*item| {
                    item.deinit(gpa);
                }
                list.deinit(gpa);
            }

            while (true) {
                const peek = try self.iter.peek() orelse return Error.ParseError;
                if (peek.type == clibyaml.YAML_SEQUENCE_END_EVENT) {
                    try self.iter.skip();
                    return .{ .sequence = list };
                }

                try list.append(gpa, try self.parse_value(gpa));
            }
        },
        clibyaml.YAML_MAPPING_START_EVENT => {
            var map = Value.HashMap.init(gpa);
            errdefer {
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    entry.key_ptr.deinit(gpa);
                    entry.value_ptr.deinit(gpa);
                }
                map.deinit();
            }

            while (true) {
                const peek = try self.iter.peek() orelse return Error.ParseError;
                if (peek.type == clibyaml.YAML_MAPPING_END_EVENT) {
                    try self.iter.skip();
                    return .{ .mapping = map };
                }

                try map.put(try self.parse_value(gpa), try self.parse_value(gpa));
            }
        },
        else => {
            std.debug.print("Got event: {d}\n", .{next.inner.type});
            break :sw Error.ParseError;
        },
    };
}

test "parse scalar" {
    const gpa = std.testing.allocator;
    const input =
        \\foo
    ;
    var schema: Self = try .init();
    defer schema.deinit();
    schema.set_input_string(input);

    var actual = try schema.parse(gpa);
    defer actual.deinit(gpa);

    var expected: Value = try .allocString(gpa, "foo");
    defer expected.deinit(gpa);

    const ctx: Value.Context = .{};
    try std.testing.expect(ctx.eql(expected, actual));
}

test "parse sequences" {
    const gpa = std.testing.allocator;
    const input =
        \\- foo
        \\- [bar, baz]
    ;
    var schema: Self = try .init();
    defer schema.deinit();
    schema.set_input_string(input);

    var actual = try schema.parse(gpa);
    defer actual.deinit(gpa);

    var expected: Value = try .allocSequence(gpa, &.{
        try Value.allocString(gpa, "foo"),
        try Value.allocSequence(gpa, &.{
            try Value.allocString(gpa, "bar"),
            try Value.allocString(gpa, "baz"),
        }),
    });
    defer expected.deinit(gpa);

    const ctx: Value.Context = .{};
    try std.testing.expect(ctx.eql(expected, actual));
}

test "parse mappings" {
    const gpa = std.testing.allocator;
    const input =
        \\foo:
        \\  bar: baz
    ;
    var schema: Self = try .init();
    defer schema.deinit();
    schema.set_input_string(input);

    var actual = try schema.parse(gpa);
    defer actual.deinit(gpa);

    var expected: Value = try .allocMapping(gpa, &.{
        .{ try Value.allocString(gpa, "foo"), try Value.allocMapping(gpa, &.{
            .{ try Value.allocString(gpa, "bar"), try Value.allocString(gpa, "baz") },
        }) },
    });
    defer expected.deinit(gpa);

    const ctx: Value.Context = .{};
    try std.testing.expect(ctx.eql(expected, actual));
}

test "parse complex keys" {
    const gpa = std.testing.allocator;
    const input =
        \\[foo]: bar
    ;
    var schema: Self = try .init();
    defer schema.deinit();
    schema.set_input_string(input);

    var actual = try schema.parse(gpa);
    defer actual.deinit(gpa);

    var expected: Value = try .allocMapping(gpa, &.{
        .{
            try Value.allocSequence(gpa, &.{try Value.allocString(gpa, "foo")}),
            try Value.allocString(gpa, "bar"),
        },
    });
    defer expected.deinit(gpa);

    const ctx: Value.Context = .{};
    try std.testing.expect(ctx.eql(expected, actual));
}
