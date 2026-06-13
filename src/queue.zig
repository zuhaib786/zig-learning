const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T = &.{},
        count: usize = 0,
        head: usize = 0,

        pub fn init(allocator: Allocator, capacity: usize) !Self {
            return .{ .items = try allocator.alloc(T, capacity) };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.items);
            self.* = undefined;
        }
        pub fn eneque(self: *Self, item: T) !void {
            if (self.count == self.items.len) return error.Full;

            const tail = @mod(self.head + self.count, self.items.len);
            self.items[tail] = item;
            self.count += 1;
        }

        pub fn deque(self: *Self) ?T {
            if (self.count == 0) return null;
            const item = self.items[self.head];
            self.head = @mod(self.head + 1, self.items.len);
            self.count -= 1;
            return item;
        }
        pub fn peek(self: *Self) ?T {
            if (self.count == 0) return null;
            const item = self.items[self.head];
            return item;
        }
    };
}
test "Ring Buffer implementation fixed size" {
    const allocator = std.testing.allocator;
    var queue: RingBuffer([]const u8) = try .init(allocator, 10);
    defer queue.deinit(allocator);
    for (0..10) |i| {
        if (@mod(i, 2) == 0) try queue.eneque("Hello");
        if (@mod(i, 2) == 1) try queue.eneque("World");
    }
    try std.testing.expectEqual(10, queue.count);
    try std.testing.expectError(error.Full, queue.eneque("Meow"));

    for (0..10) |i| {
        if (@mod(i, 2) == 0) try std.testing.expectEqualStrings("Hello", queue.deque().?);
        if (@mod(i, 2) == 1) try std.testing.expectEqualStrings("World", queue.deque().?);
    }
}
test "Ring Buffer implementation wrap around" {
    const allocator = std.testing.allocator;
    var queue: RingBuffer([]const u8) = try .init(allocator, 3);
    defer queue.deinit(allocator);
    for (0..2) |i| {
        if (@mod(i, 2) == 0) try queue.eneque("Hello");
        if (@mod(i, 2) == 1) try queue.eneque("World");
    }
    try std.testing.expectEqual(2, queue.count);
    try std.testing.expectEqualStrings("Hello", queue.deque().?);
    try std.testing.expectEqualStrings("World", queue.deque().?);
    for (0..2) |i| {
        if (@mod(i, 2) == 0) try queue.eneque("Hello");
        if (@mod(i, 2) == 1) try queue.eneque("World");
    }

    try std.testing.expectEqual(2, queue.count);
    try std.testing.expectEqualStrings("Hello", queue.deque().?);
    try std.testing.expectEqualStrings("World", queue.deque().?);
}
