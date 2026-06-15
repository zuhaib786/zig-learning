const std = @import("std");
const lzig = @import("lzig");
const Treap = lzig.treap.Treap;
const MinHeap = lzig.heap.MinHeap;

fn lessThan(a: u32, b: u32) bool {
    return a < b;
}

fn monoNanos() u64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.CLOCK.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn benchTreapInsert() !void {
    const N: u32 = 1_000_000;

    // Arena: isolates the algorithm's cost from per-node free cost.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tree = Treap(u32).init(a, lessThan);

    const start = monoNanos();
    var i: u32 = 0;
    while (i < N) : (i += 1) {
        try tree.insert(i); // ascending keys: the worst case for a plain BST
    }
    const insert_ns = monoNanos() - start;

    const ms: f64 = @as(f64, @floatFromInt(insert_ns)) / 1e6;
    const per_op: f64 = @as(f64, @floatFromInt(insert_ns)) / @as(f64, @floatFromInt(N));
    const ideal: f64 = @log2(@as(f64, @floatFromInt(N)));
    std.debug.print(
        \\[treap insert] {d} ascending keys
        \\  total insert : {d:.1} ms
        \\  per insert   : {d:.0} ns/op
        \\  tree height  : {d}  (ideal log2 N ≈ {d:.0}; a plain BST here would be {d})
        \\
    , .{ N, ms, per_op, tree.height(), ideal, N });
}

fn benchHeapInsertPop() !void {
    const N: u32 = 1_000_000;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Generate the inputs up front so the RNG stays out of the timed sections.
    var prng = std.Random.DefaultPrng.init(0x1234);
    const rand = prng.random();
    const values = try a.alloc(u32, N);
    for (values) |*v| v.* = rand.int(u32);

    var h = MinHeap(u32).init(a, lessThan);
    defer h.deinit();

    const t0 = monoNanos();
    for (values) |v| try h.insert(v);
    const insert_ns = monoNanos() - t0;

    // Popping everything is heap-sort; verify ascending order as a sanity check.
    const t1 = monoNanos();
    var prev: u32 = 0;
    var sorted = true;
    var count: usize = 0;
    while (h.pop()) |v| {
        if (v < prev) sorted = false;
        prev = v;
        count += 1;
    }
    const pop_ns = monoNanos() - t1;

    const ins_ms: f64 = @as(f64, @floatFromInt(insert_ns)) / 1e6;
    const ins_per: f64 = @as(f64, @floatFromInt(insert_ns)) / @as(f64, @floatFromInt(N));
    const pop_ms: f64 = @as(f64, @floatFromInt(pop_ns)) / 1e6;
    const pop_per: f64 = @as(f64, @floatFromInt(pop_ns)) / @as(f64, @floatFromInt(N));
    std.debug.print(
        \\[minheap insert+pop] {d} random u32
        \\  insert total : {d:.1} ms  ({d:.0} ns/op)
        \\  pop total    : {d:.1} ms  ({d:.0} ns/op)
        \\  popped count : {d}   sorted: {}
        \\
    , .{ N, ins_ms, ins_per, pop_ms, pop_per, count, sorted });
}

pub fn main() !void {
    try benchTreapInsert();
    try benchHeapInsertPop();
}
