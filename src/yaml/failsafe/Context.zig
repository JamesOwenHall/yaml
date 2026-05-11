//! This struct implements a HashMap Context for Value keys. The use of slices in Values (strings and sequences)
//! prevents the use of AutoHashMap.
const std = @import("std");
const Value = @import("value.zig").Value;

pub fn hash(self: @This(), key: Value) u64 {
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
