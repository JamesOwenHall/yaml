const std = @import("std");
const Context = @import("Context.zig");

pub const Value = union(enum) {
    pub const HashMap = std.HashMap(Value, Value, Context, 80);
    pub const mapping_load_factor = 80;

    string: []const u8,
    sequence: std.ArrayList(Value),
    mapping: HashMap,

    pub fn allocString(gpa: std.mem.Allocator, str: []const u8) !Value {
        return .{ .string = try gpa.dupe(u8, str) };
    }

    pub fn allocSequence(gpa: std.mem.Allocator, items: []const Value) !Value {
        var list = try std.ArrayList(Value).initCapacity(gpa, items.len);
        errdefer list.deinit(gpa);

        try list.appendSlice(gpa, items);
        return .{ .sequence = list };
    }

    pub fn allocMapping(gpa: std.mem.Allocator, entries: []const [2]Value) !Value {
        var map = HashMap.init(gpa);
        errdefer map.deinit();

        for (entries) |entry| {
            try map.put(entry[0], entry[1]);
        }

        return .{ .mapping = map };
    }

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
};

test "context with strings" {
    const gpa = std.testing.allocator;

    var v1: Value = try .allocString(gpa, "foo");
    defer v1.deinit(gpa);
    var v2: Value = try .allocString(gpa, "foo");
    defer v2.deinit(gpa);
    var v3: Value = try .allocString(gpa, "bar");
    defer v3.deinit(gpa);

    const ctx: Context = .{};
    try std.testing.expectEqual(ctx.hash(v1), ctx.hash(v2));
    try std.testing.expect(ctx.hash(v1) != ctx.hash(v3));
    try std.testing.expect(ctx.eql(v1, v2));
    try std.testing.expect(!ctx.eql(v1, v3));
}

test "context with sequences" {
    const gpa = std.testing.allocator;

    var v1: Value = try .allocSequence(gpa, &.{ try .allocString(gpa, "foo"), try .allocString(gpa, "bar") });
    defer v1.deinit(gpa);
    var v2: Value = try .allocSequence(gpa, &.{ try .allocString(gpa, "foo"), try .allocString(gpa, "bar") });
    defer v2.deinit(gpa);
    var v3: Value = try .allocSequence(gpa, &.{ try .allocString(gpa, "foo"), try .allocString(gpa, "baz") });
    defer v3.deinit(gpa);

    const ctx: Context = .{};
    try std.testing.expectEqual(ctx.hash(v1), ctx.hash(v2));
    try std.testing.expect(ctx.hash(v1) != ctx.hash(v3));
    try std.testing.expect(ctx.eql(v1, v2));
    try std.testing.expect(!ctx.eql(v1, v3));
}

test "context with mappings" {
    const gpa = std.testing.allocator;

    var v1: Value = try .allocMapping(gpa, &.{.{ try Value.allocString(gpa, "foo"), try Value.allocString(gpa, "bar") }});
    defer v1.deinit(gpa);
    var v2: Value = try .allocMapping(gpa, &.{.{ try Value.allocString(gpa, "foo"), try Value.allocString(gpa, "bar") }});
    defer v2.deinit(gpa);
    var v3: Value = try .allocMapping(gpa, &.{.{ try Value.allocString(gpa, "foo"), try Value.allocString(gpa, "baz") }});
    defer v3.deinit(gpa);

    const ctx: Context = .{};
    try std.testing.expectEqual(ctx.hash(v1), ctx.hash(v2));
    try std.testing.expect(ctx.hash(v1) != ctx.hash(v3));
    try std.testing.expect(ctx.eql(v1, v2));
    try std.testing.expect(!ctx.eql(v1, v3));
}

test "context with different types" {
    const gpa = std.testing.allocator;

    var v1: Value = try .allocString(gpa, "foo");
    defer v1.deinit(gpa);
    var v2: Value = try .allocSequence(gpa, &.{try .allocString(gpa, "foo")});
    defer v2.deinit(gpa);
    var v3: Value = try .allocMapping(gpa, &.{.{ try Value.allocString(gpa, "foo"), try Value.allocString(gpa, "") }});
    defer v3.deinit(gpa);

    const ctx: Context = .{};
    try std.testing.expect(ctx.hash(v1) != ctx.hash(v2));
    try std.testing.expect(ctx.hash(v1) != ctx.hash(v3));
    try std.testing.expect(ctx.hash(v2) != ctx.hash(v3));
    try std.testing.expect(!ctx.eql(v1, v2));
    try std.testing.expect(!ctx.eql(v1, v3));
    try std.testing.expect(!ctx.eql(v2, v3));
}
