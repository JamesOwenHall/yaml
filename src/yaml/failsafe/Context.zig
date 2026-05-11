//! This struct implements a HashMap Context for Value keys. The use of slices in Values (strings and sequences)
//! prevents the use of AutoHashMap.
const std = @import("std");
const Value = @import("value.zig").Value;
const Context = @This();

pub fn hash(self: Context, key: Value) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(&.{@as(u8, @intFromEnum(key))});

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

pub fn eql(self: Context, key1: Value, key2: Value) bool {
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
