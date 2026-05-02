const std = @import("std");
const clibyaml = @import("clibyaml");
const Error = @import("error.zig").Error;
const EventIterator = @import("EventIterator.zig");
const Self = @This();

iter: EventIterator,

pub const Value = union(enum) {
    pub const mapping_load_factor = 80;

    string: []const u8,
    sequence: std.ArrayList(Value),
    mapping: std.HashMap(Value, Value, Context, mapping_load_factor),

    pub fn deinit(self: *Value, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .string => |str| gpa.free(str),
            .sequence => |*list| {
                for (list.items) |*item| {
                    item.deinit(gpa);
                }
                list.deinit(gpa);
            },
            .mapping => |*map| {
                var iter = map.iterator();
                while (iter.next()) |entry| {
                    entry.key_ptr.deinit(gpa);
                    entry.value_ptr.deinit(gpa);
                }
                map.deinit();
            },
        }
    }

    pub const Context = struct {
        pub fn hash(self: @This(), key: Value) u64 {
            var hasher = std.hash.Wyhash.init(0);

            switch (key) {
                .string => |str| hasher.update(str),
                .sequence => |seq| {
                    for (seq.items) |item| {
                        const item_hash = self.hash(item);
                        hasher.update(std.mem.asBytes(&item_hash));
                    }
                },
                .mapping => |map| {
                    var iter = map.iterator();
                    while (iter.next()) |entry| {
                        const key_hash = self.hash(entry.key_ptr.*);
                        const value_hash = self.hash(entry.value_ptr.*);
                        hasher.update(std.mem.asBytes(&key_hash));
                        hasher.update(std.mem.asBytes(&value_hash));
                    }
                },
            }

            return hasher.final();
        }

        pub fn eql(self: @This(), key1: Value, key2: Value) bool {
            switch (key1) {
                .string => |s1| switch (key2) {
                    .string => |s2| return std.mem.eql(u8, s1, s2),
                    else => return false,
                },
                .sequence => |seq1| switch (key2) {
                    .sequence => |seq2| {
                        if (seq1.items.len != seq2.items.len) {
                            return false;
                        }
                        for (0..seq1.items.len) |i| {
                            if (!self.eql(seq1.items[i], seq2.items[i])) {
                                return false;
                            }
                        }
                        return true;
                    },
                    else => return false,
                },
                .mapping => |map1| {
                    switch (key2) {
                        .mapping => |map2| {
                            if (map1.count() != map2.count()) {
                                return false;
                            }

                            var m1_iter = map1.iterator();
                            while (m1_iter.next()) |m1_entry| {
                                const m2_val = map2.get(m1_entry.key_ptr.*);

                                if (m2_val == null) {
                                    return false;
                                } else if (!self.eql(m1_entry.value_ptr.*, m2_val.?)) {
                                    return false;
                                }
                            }
                        },
                        else => return false,
                    }
                },
            }

            return true;
        }
    };
};

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
            var map = std.HashMap(Value, Value, Value.Context, 80).init(gpa);
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

    var expected = Value{ .string = try gpa.dupe(u8, "foo") };
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

    var inner_list = std.ArrayList(Value).empty;
    try inner_list.append(gpa, .{ .string = try gpa.dupe(u8, "bar") });
    try inner_list.append(gpa, .{ .string = try gpa.dupe(u8, "baz") });

    var outer_list = std.ArrayList(Value).empty;
    try outer_list.append(gpa, .{ .string = try gpa.dupe(u8, "foo") });
    try outer_list.append(gpa, .{ .sequence = inner_list });

    var expected = Value{ .sequence = outer_list };
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

    var inner_map = std.HashMap(Value, Value, Value.Context, Value.mapping_load_factor).init(gpa);
    try inner_map.put(
        Value{ .string = try gpa.dupe(u8, "bar") },
        Value{ .string = try gpa.dupe(u8, "baz") },
    );

    var outer_map = std.HashMap(Value, Value, Value.Context, Value.mapping_load_factor).init(gpa);
    try outer_map.put(
        Value{ .string = try gpa.dupe(u8, "foo") },
        Value{ .mapping = inner_map },
    );

    var expected = Value{ .mapping = outer_map };
    defer expected.deinit(gpa);

    const ctx: Value.Context = .{};
    try std.testing.expect(ctx.eql(expected, actual));
}
