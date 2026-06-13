const std = @import("std");

pub fn lowerbound(comptime T: type, items: []const T, target: T, comptime lessThan: fn (T, T) bool) usize {
    var low: usize = 0;
    var high: usize = items.len;
    while (low < high) {
        const mid = low + @divFloor(high - low, 2);
        if (lessThan(items[mid], target)) {
            low = mid + 1;
        } else {
            high = mid;
        }
    }
    return low;
}

pub fn contains(comptime T: type, items: []const T, target: T, comptime lessThan: fn (T, T) bool) bool {
    const index = lowerbound(T, items, target, lessThan);
    return index < items.len and !lessThan(items[index], target) and !lessThan(target, items[index]);
}

pub fn insertionSort(comptime T: type, items: []T, comptime lessThan: fn (T, T) bool) void {
    if (items.len == 0) return;
    for (1..items.len) |i| {
        const key = items[i];
        var j = i;
        while (j > 0 and lessThan(key, items[j - 1])) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = key;
    }
}

test "lower bound" {
    const items = [_]u32{ 10, 20, 30, 40 };
    const lessThan = struct {
        fn less(a: u32, b: u32) bool {
            return a < b;
        }
    }.less;
    try std.testing.expectEqual(2, lowerbound(u32, &items, 30, lessThan));
    try std.testing.expectEqual(2, lowerbound(u32, &items, 25, lessThan));
    try std.testing.expectEqual(0, lowerbound(u32, &items, 5, lessThan));
    try std.testing.expectEqual(items.len, lowerbound(u32, &items, 99, lessThan));
}

test "lower bound empty" {
    const items = [_]u32{};
    const lessThan = struct {
        fn less(a: u32, b: u32) bool {
            return a < b;
        }
    }.less;

    try std.testing.expectEqual(0, lowerbound(u32, &items, 30, lessThan));
    try std.testing.expectEqual(0, lowerbound(u32, &items, 25, lessThan));
    try std.testing.expectEqual(0, lowerbound(u32, &items, 5, lessThan));
    try std.testing.expectEqual(items.len, lowerbound(u32, &items, 99, lessThan));
}

test "insertion sort" {
    var empty = [_]u32{};
    const lessThan = struct {
        fn less(a: u32, b: u32) bool {
            return a < b;
        }
    }.less;
    const ctxLessThan = struct {
        fn less(_: void, a: u32, b: u32) bool {
            return a < b;
        }
    }.less;
    insertionSort(u32, &empty, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{}), empty[0..]);
    var single_elem = [_]u32{10};
    insertionSort(u32, &single_elem, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{10}), single_elem[0..]);
    var already_sorted = [_]u32{ 10, 20, 30, 40 };
    insertionSort(u32, &already_sorted, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{ 10, 20, 30, 40 }), already_sorted[0..]);
    var reverse_sorted = [_]u32{ 40, 30, 20, 10 };
    insertionSort(u32, &reverse_sorted, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{ 10, 20, 30, 40 }), reverse_sorted[0..]);
    var random_order = [_]u32{ 10, 40, 20, 30, 90, 100, 120, 11, 15 };
    var random_order_dup = [_]u32{ 10, 40, 20, 30, 90, 100, 120, 11, 15 };
    insertionSort(u32, &random_order, lessThan);
    std.mem.sort(u32, &random_order_dup, {}, ctxLessThan);
    try std.testing.expectEqualSlices(u32, random_order_dup[0..], random_order[0..]);
}
