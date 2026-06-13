const std = @import("std");
const strings = @import("strings.zig");
const Allocator = std.mem.Allocator;
const Map = std.StringHashMap;

const WordCount = struct { count: usize, word: []const u8 };

/// Builds a word -> count map. The map OWNS its keys (duped on first insert).
/// Caller must free the keys and then deinit — use `freeCounts`, which does both.
pub fn countWords(allocator: Allocator, text: []const u8) !Map(u32) {
    var word_map = Map(u32).init(allocator);
    var tokens = std.mem.tokenizeAny(u8, text, " \r\t\n");
    while (tokens.next()) |token| {
        const gop = try word_map.getOrPut(token);
        if (!gop.found_existing) {
            // New key: the map only stored our (borrowed) `token` slice, which
            // points into `text`. Replace it with an owned copy so the map is
            // self-contained and safe to keep after `text` is gone.
            gop.key_ptr.* = try strings.dup(allocator, token);
            gop.value_ptr.* = 0;
        }
        gop.value_ptr.* += 1;
    }
    return word_map;
}

/// Frees the map's owned keys, then the map itself. Takes the map by pointer
/// because `deinit` mutates it.
pub fn freeCounts(comptime T: type, allocator: Allocator, map: *Map(T)) void {
    var it = map.keyIterator();
    while (it.next()) |key_ptr| allocator.free(key_ptr.*);
    map.deinit();
}

fn moreFrequent(_: void, a: WordCount, b: WordCount) bool {
    if (a.count != b.count) return a.count > b.count; // higher count first
    return std.mem.lessThan(u8, a.word, b.word); // tie-break: alphabetical (deterministic)
}

/// Returns up to `k` words sorted by descending frequency.
/// Caller owns the returned slice and must free it. The `word` fields BORROW
/// the map's keys: they are valid only while `map` is alive — do NOT free them.
pub fn topK(allocator: Allocator, map: Map(u32), k: usize) ![]WordCount {
    var list: std.ArrayList(WordCount) = .empty;
    errdefer list.deinit(allocator);
    var it = map.iterator();
    while (it.next()) |entry| {
        try list.append(allocator, .{ .word = entry.key_ptr.*, .count = entry.value_ptr.* });
    }
    std.mem.sort(WordCount, list.items, {}, moreFrequent);
    if (list.items.len > k) list.shrinkRetainingCapacity(k);
    return list.toOwnedSlice(allocator); // exact-size allocation of <= k items
}

test "countWords counts and is leak-free" {
    const a = std.testing.allocator;
    var map = try countWords(a, "a b a c a b");
    defer freeCounts(u32, a, &map);
    try std.testing.expectEqual(@as(u32, 3), map.get("a").?);
    try std.testing.expectEqual(@as(u32, 2), map.get("b").?);
    try std.testing.expectEqual(@as(u32, 1), map.get("c").?);
}

test "topK returns the k most frequent" {
    const a = std.testing.allocator;
    var map = try countWords(a, "a b a c a b");
    defer freeCounts(u32, a, &map);
    const top = try topK(a, map, 2);
    defer a.free(top);
    try std.testing.expectEqual(@as(usize, 2), top.len);
    try std.testing.expectEqualStrings("a", top[0].word);
    try std.testing.expectEqual(@as(usize, 3), top[0].count);
    try std.testing.expectEqualStrings("b", top[1].word);
}

test "topK clamps when k exceeds vocabulary" {
    const a = std.testing.allocator;
    var map = try countWords(a, "x y x");
    defer freeCounts(u32, a, &map);
    const top = try topK(a, map, 100);
    defer a.free(top);
    try std.testing.expectEqual(@as(usize, 2), top.len); // only 2 distinct words
}
