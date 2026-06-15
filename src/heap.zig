const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn MinHeap(comptime T: type) type {
    return struct {
        const Self = @This();
        list: ArrayList(T),
        alloctor: Allocator,
        lessThan: *const fn (T, T) bool,

        pub fn init(allocator: Allocator, lessThan: *const fn (T, T) bool) Self {
            return .{
                .alloctor = allocator,
                .lessThan = lessThan,
                .list = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit(self.alloctor);
        }
        pub fn len(self: Self) usize {
            return self.list.items.len;
        }
        pub fn insert(self: *Self, value: T) !void {
            try self.list.append(self.alloctor, value);
            self.bubbleUp(self.list.items.len - 1);
        }

        pub fn pop(self: *Self) ?T {
            const n = self.len();
            if (n == 0) return null;
            const ans = self.list.items[0];
            if (n > 1) {
                std.mem.swap(T, &self.list.items[0], &self.list.items[n - 1]);
            }
            _ = self.list.pop();
            self.bubbleDown(0);
            return ans;
        }

        fn bubbleUp(self: *Self, index: usize) void {
            var i = index;
            while (i > 0) {
                const p = (i - 1) / 2;
                if (!self.lessThan(self.list.items[i], self.list.items[p])) {
                    break;
                }
                std.mem.swap(T, &self.list.items[p], &self.list.items[i]);
                i = p;
            }
        }

        fn bubbleDown(self: *Self, index: usize) void {
            const n = self.list.items.len;
            var i = index;
            while (true) {
                const l = 2 * i + 1;
                const r = 2 * i + 2;
                var best = i;
                if (l < n and self.lessThan(self.list.items[l], self.list.items[best])) best = l;
                if (r < n and self.lessThan(self.list.items[r], self.list.items[best])) best = r;
                if (best == i) break;
                std.mem.swap(T, &self.list.items[best], &self.list.items[i]);
                i = best;
            }
        }
    };
}

const testing = std.testing;

fn lessThanU32(a: u32, b: u32) bool {
    return a < b;
}

const Item = struct { d: u64, node: usize };
fn itemLess(a: Item, b: Item) bool {
    return a.d < b.d;
}

test "minheap: empty heap pops null" {
    var h = MinHeap(u32).init(testing.allocator, &lessThanU32);
    defer h.deinit();
    try testing.expectEqual(0, h.len());
    try testing.expectEqual(null, h.pop());
}

test "minheap: single element" {
    var h = MinHeap(u32).init(testing.allocator, &lessThanU32);
    defer h.deinit();
    try h.insert(42);
    try testing.expectEqual(1, h.len());
    try testing.expectEqual(42, h.pop().?);
    try testing.expectEqual(0, h.len());
    try testing.expectEqual(null, h.pop());
}

// The discriminating test: insert shuffled, pop everything -> sorted ascending.
// This exercises both bubbleUp (on insert) and bubbleDown (on pop).
test "minheap: popping yields ascending order (heap-sort)" {
    var h = MinHeap(u32).init(testing.allocator, &lessThanU32);
    defer h.deinit();
    for ([_]u32{ 5, 3, 8, 1, 9, 2, 7, 4, 6, 0 }) |x| try h.insert(x);
    try testing.expectEqual(10, h.len());

    var out: [10]u32 = undefined;
    var i: usize = 0;
    while (h.pop()) |v| {
        out[i] = v;
        i += 1;
    }
    try testing.expectEqual(10, i);
    try testing.expectEqualSlices(u32, &.{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }, &out);
    try testing.expectEqual(0, h.len());
}

test "minheap: handles duplicate priorities" {
    var h = MinHeap(u32).init(testing.allocator, &lessThanU32);
    defer h.deinit();
    for ([_]u32{ 4, 1, 4, 1, 4, 1 }) |x| try h.insert(x);
    try testing.expectEqual(1, h.pop().?);
    try testing.expectEqual(1, h.pop().?);
    try testing.expectEqual(1, h.pop().?);
    try testing.expectEqual(4, h.pop().?);
    try testing.expectEqual(4, h.pop().?);
    try testing.expectEqual(4, h.pop().?);
    try testing.expectEqual(null, h.pop());
}

// Interleaving forces a new min to surface mid-stream, stressing both sifts.
test "minheap: interleaved insert and pop keeps the min on top" {
    var h = MinHeap(u32).init(testing.allocator, &lessThanU32);
    defer h.deinit();
    try h.insert(5);
    try h.insert(3);
    try testing.expectEqual(3, h.pop().?);
    try h.insert(1);
    try h.insert(4);
    try testing.expectEqual(1, h.pop().?);
    try testing.expectEqual(4, h.pop().?);
    try testing.expectEqual(5, h.pop().?);
    try testing.expectEqual(null, h.pop());
}

// Mirrors how Dijkstra will use it: order struct payloads by a priority field.
test "minheap: orders struct payloads by priority (dijkstra-style)" {
    var h = MinHeap(Item).init(testing.allocator, &itemLess);
    defer h.deinit();
    try h.insert(.{ .d = 7, .node = 0 });
    try h.insert(.{ .d = 2, .node = 1 });
    try h.insert(.{ .d = 5, .node = 2 });
    try h.insert(.{ .d = 1, .node = 3 });
    try testing.expectEqual(3, h.pop().?.node); // d=1
    try testing.expectEqual(1, h.pop().?.node); // d=2
    try testing.expectEqual(2, h.pop().?.node); // d=5
    try testing.expectEqual(0, h.pop().?.node); // d=7
    try testing.expectEqual(null, h.pop());
}
