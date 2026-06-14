const std = @import("std");
const Allocator = std.mem.Allocator;

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

pub fn mergeSort(comptime T: type, items: []T, allocator: Allocator, comptime lessThan: fn (T, T) bool) !void {
    if (items.len <= 1) {
        return;
    }
    const mid = items.len / 2;
    try mergeSort(T, items[0..mid], allocator, lessThan);
    try mergeSort(T, items[mid..], allocator, lessThan);
    try merge(T, items, mid, allocator, lessThan);
}

fn merge(comptime T: type, items: []T, mid: usize, allocator: Allocator, comptime lessThan: fn (T, T) bool) !void {
    const out = try allocator.alloc(T, items.len);
    defer allocator.free(out);
    @memcpy(out, items);
    var i: usize = 0;
    var j: usize = mid;
    var k: usize = 0;
    while (i < mid and j < items.len) {
        if (!lessThan(out[j], out[i])) {
            items[k] = out[i];
            i += 1;
        } else {
            items[k] = out[j];
            j += 1;
        }
        k += 1;
    }
    while (i < mid) : ({
        i += 1;
        k += 1;
    }) {
        items[k] = out[i];
    }
    while (j < items.len) : ({
        j += 1;
        k += 1;
    }) {
        items[k] = out[j];
    }
}

pub fn quickSort(comptime T: type, items: []T, lessThan: fn (T, T) bool) void {
    if (items.len <= 1) return;
    const mid = partition(T, items, lessThan);
    quickSort(T, items[0..mid], lessThan);
    quickSort(T, items[mid + 1 ..], lessThan);
}

fn partition(comptime T: type, items: []T, lessThan: fn (T, T) bool) usize {
    const pivot = items[items.len - 1];
    var i: usize = 0;
    for (0..items.len - 1) |j| {
        if (lessThan(items[j], pivot)) {
            std.mem.swap(T, &items[i], &items[j]);
            i += 1;
        }
    }
    std.mem.swap(T, &items[i], &items[items.len - 1]);
    return i;
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

test "merge sort" {
    var empty = [_]u32{};
    const allocator = std.testing.allocator;
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
    try mergeSort(u32, &empty, allocator, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{}), empty[0..]);
    var single_elem = [_]u32{10};
    try mergeSort(u32, &single_elem, allocator, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{10}), single_elem[0..]);
    var already_sorted = [_]u32{ 10, 20, 30, 40 };
    try mergeSort(u32, &already_sorted, allocator, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{ 10, 20, 30, 40 }), already_sorted[0..]);
    var reverse_sorted = [_]u32{ 40, 30, 20, 10 };
    try mergeSort(u32, &reverse_sorted, allocator, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{ 10, 20, 30, 40 }), reverse_sorted[0..]);
    var random_order = [_]u32{ 10, 40, 20, 30, 90, 100, 120, 11, 15 };
    var random_order_dup = [_]u32{ 10, 40, 20, 30, 90, 100, 120, 11, 15 };
    try mergeSort(u32, &random_order, allocator, lessThan);
    std.mem.sort(u32, &random_order_dup, {}, ctxLessThan);
    try std.testing.expectEqualSlices(u32, random_order_dup[0..], random_order[0..]);
}
test "merge sort stability" {
    const allocator = std.testing.allocator;
    const Value = struct { key: u32, orig: usize };
    var array = [_]Value{ .{ .key = 1, .orig = 1 }, .{ .key = 1, .orig = 2 }, .{ .key = 2, .orig = 3 }, .{ .key = 1, .orig = 4 } };

    const lessThan = struct {
        fn less(a: Value, b: Value) bool {
            return a.key < b.key;
        }
    }.less;
    try mergeSort(Value, &array, allocator, lessThan);
    try std.testing.expectEqualSlices(Value, &([_]Value{
        .{ .key = 1, .orig = 1 },
        .{ .key = 1, .orig = 2 },
        .{ .key = 1, .orig = 4 },
        .{ .key = 2, .orig = 3 },
    }), array[0..]);
}

test "quick sort" {
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
    quickSort(u32, &empty, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{}), empty[0..]);
    var single_elem = [_]u32{10};
    quickSort(u32, &single_elem, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{10}), single_elem[0..]);
    var already_sorted = [_]u32{ 10, 20, 30, 40 };
    quickSort(u32, &already_sorted, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{ 10, 20, 30, 40 }), already_sorted[0..]);
    var reverse_sorted = [_]u32{ 40, 30, 20, 10 };
    quickSort(u32, &reverse_sorted, lessThan);
    try std.testing.expectEqualSlices(u32, &([_]u32{ 10, 20, 30, 40 }), reverse_sorted[0..]);
    var random_order = [_]u32{ 10, 40, 20, 30, 90, 100, 120, 11, 15 };
    var random_order_dup = [_]u32{ 10, 40, 20, 30, 90, 100, 120, 11, 15 };
    quickSort(u32, &random_order, lessThan);
    std.mem.sort(u32, &random_order_dup, {}, ctxLessThan);
    try std.testing.expectEqualSlices(u32, random_order_dup[0..], random_order[0..]);
}
