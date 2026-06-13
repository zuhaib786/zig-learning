const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();
        items: []T = &.{},
        len: usize = 0,

        pub fn push(self: *Self, allocator: Allocator, item: T) !void {
            if (self.len == self.items.len) {
                const new_cap = @max(8, self.len * 2);
                self.items = try allocator.realloc(self.items, new_cap);
            }
            self.items[self.len] = item;
            self.len += 1;
        }
        pub fn get(self: *Self, index: usize) ?T {
            if (index >= self.len) {
                return null;
            }
            return self.items[index];
        }
        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            self.len -= 1;
            return self.items[self.len];
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.items);
            self.* = .{};
        }

        pub fn toOwnedSlice(self: *Self, allocator: Allocator) ![]T {
            const out = try allocator.realloc(self.items, self.len);
            self.items = &.{};
            self.len = 0;
            return out;
        }
    };
}

test "List works for strings and integers" {
    var list1: List(u8) = .{};
    var list2: List([]const u8) = .{};
    const allocator = std.testing.allocator;
    defer list1.deinit(allocator);
    defer list2.deinit(allocator);
    try std.testing.expect(list1.pop() == null);
    try std.testing.expect(list2.pop() == null);
    for (0..10) |i| {
        try list1.push(allocator, @intCast(i));
    }
    try std.testing.expectEqual(10, list1.len);
    for (0..50) |i| {
        if (@mod(i, 2) == 0) {
            try list2.push(allocator, "Hello ");
        }
        if (@mod(i, 2) == 1) {
            try list2.push(allocator, "World");
        }
    }
    try std.testing.expectEqual(50, list2.len);
    try std.testing.expect(list2.get(list2.len) == null);
    try std.testing.expect(list1.get(list1.len) == null);
    const out1 = try list1.toOwnedSlice(allocator);
    defer allocator.free(out1);
    try std.testing.expectEqualSlices(u8, &[10]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, out1);
    const out2 = try list2.toOwnedSlice(allocator);
    defer allocator.free(out2);
    try std.testing.expectEqualSlices([]const u8, &([2][]const u8{ "Hello ", "World" } ** 25), out2);
}
