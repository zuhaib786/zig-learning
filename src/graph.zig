const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const queue = @import("queue.zig");
const heap = @import("heap.zig");
const Heap = heap.MinHeap;
const INF: u64 = 1e9 + 7;

pub const Graph = struct {
    const Self = @This();
    const Edge = struct { to: usize, w: u32 };
    adj: []ArrayList(Edge),
    allocator: Allocator,

    pub fn init(allocator: Allocator, n: usize) !Self {
        const graph: Self = .{
            .allocator = allocator,
            .adj = try allocator.alloc(ArrayList(Edge), n),
        };
        for (graph.adj) |*list| {
            list.* = .empty;
        }
        return graph;
    }

    pub fn deinit(self: *Self) void {
        for (self.adj) |*list| {
            list.deinit(self.allocator);
        }
        self.allocator.free(self.adj);
    }
    pub fn addEdge(self: *Self, u: usize, v: usize, w: u32) !void {
        try self.adj[u].append(self.allocator, .{ .to = v, .w = w });
    }

    /// Call to bfs returnes order of the entry in array that is owned by the user.
    /// Callee is responsible for deallocation using the same allocator
    pub fn bfs(self: *Self, start: usize) ![]usize {
        var order: ArrayList(usize) = .empty;
        const n = self.adj.len;
        var visited: []bool = try self.allocator.alloc(bool, n);
        defer self.allocator.free(visited);
        for (0..n) |i| {
            visited[i] = false;
        }
        errdefer order.deinit(self.allocator);
        try order.append(self.allocator, start);
        var q: queue.RingBuffer(usize) = try .init(self.allocator, self.adj.len);
        defer q.deinit(self.allocator);
        try q.eneque(start);
        visited[start] = true;
        while (q.deque()) |u| {
            for (self.adj[u].items) |e| {
                if (!visited[e.to]) {
                    visited[e.to] = true;
                    try order.append(self.allocator, e.to);
                    try q.eneque(e.to);
                }
            }
        }
        return try order.toOwnedSlice(self.allocator);
    }
    pub fn dfs(self: *Self, u: usize, visited: []bool) void {
        visited[u] = true;
        for (self.adj[u].items) |e| {
            if (!visited[e.to]) {
                self.dfs(e.to, visited);
            }
        }
    }

    pub fn topologicalSort(self: *Self) ![]usize {
        const n = self.adj.len;
        var indeg: []usize = try self.allocator.alloc(usize, n);
        defer self.allocator.free(indeg);
        var order: ArrayList(usize) = .empty;
        errdefer order.deinit(self.allocator);
        for (0..n) |i| indeg[i] = 0;
        for (0..n) |u| {
            for (self.adj[u].items) |e| indeg[e.to] += 1;
        }
        var q: queue.RingBuffer(usize) = try .init(self.allocator, n);
        defer q.deinit(self.allocator);
        for (0..n) |i| if (indeg[i] == 0) try q.eneque(i);
        while (q.deque()) |u| {
            try order.append(self.allocator, u);
            for (self.adj[u].items) |e| {
                indeg[e.to] -= 1;
                if (indeg[e.to] == 0) {
                    try q.eneque(e.to);
                }
            }
        }
        for (0..n) |i| {
            if (indeg[i] != 0)
                return error.CycleError;
        }
        return try order.toOwnedSlice(self.allocator);
    }

    pub fn dijikstra(self: *Self, src: usize) ![]u64 {
        const n = self.adj.len;
        var distances: []u64 = try self.allocator.alloc(u64, n);
        errdefer self.allocator.free(distances);
        for (0..n) |i| distances[i] = INF;
        distances[src] = 0;
        const data = struct { d: u64, u: usize };
        const lessThan = struct {
            fn less(a: data, b: data) bool {
                return a.d < b.d;
            }
        }.less;
        var pq: Heap(data) = .init(self.allocator, &lessThan);
        defer pq.deinit();
        try pq.insert(.{ .d = 0, .u = src });
        while (pq.pop()) |d| {
            const u = d.u;
            if (d.d > distances[u]) continue;
            for (self.adj[u].items) |e| {
                const v = e.to;
                if (distances[v] > d.d + e.w) {
                    distances[v] = d.d + e.w;
                    try pq.insert(.{ .d = d.d + e.w, .u = v });
                }
            }
        }
        return distances;
    }
};

pub fn parseGraph(allocator: Allocator, text: []const u8) !Graph {
    var lines = std.mem.tokenizeAny(u8, text, "\n");
    const first = lines.next() orelse return error.EmptyInput;
    const n = try std.fmt.parseInt(usize, std.mem.trim(u8, first, " "), 10);
    var graph: Graph = try .init(allocator, n);
    errdefer graph.deinit();
    while (lines.next()) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, "\r\t ");
        const u_s = tokens.next() orelse continue;
        const v_s = tokens.next() orelse error.BadEdge;
        const u = try std.fmt.parseInt(usize, u_s, 10);
        const v = try std.fmt.parseInt(usize, v_s, 10);
        if (u >= n or v >= n) return error.NodeOutOfRange;
        const w = try std.fmt.parseInt(u32, tokens.next() orelse "1", 10);
        try graph.addEdge(u, v, w);
    }
    return graph;
}

const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;
const expectError = testing.expectError;

// A topological order is valid iff every edge u->v places u before v.
// Orders aren't unique, so we check the constraint rather than an exact slice.
fn assertValidTopo(g: *Graph, order: []const usize) !void {
    const n = g.adj.len;
    try expectEqual(n, order.len);
    const pos = try testing.allocator.alloc(usize, n);
    defer testing.allocator.free(pos);
    for (order, 0..) |node, i| pos[node] = i;
    for (0..n) |u| {
        for (g.adj[u].items) |e| try expect(pos[u] < pos[e.to]);
    }
}

test "graph: bfs visit order from a source" {
    const a = testing.allocator;
    var g = try Graph.init(a, 4);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(0, 2, 1);
    try g.addEdge(1, 3, 1);
    try g.addEdge(2, 3, 1);
    const order = try g.bfs(0);
    defer a.free(order);
    try expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, order);
}

test "graph: bfs ignores unreachable (disconnected) nodes" {
    const a = testing.allocator;
    var g = try Graph.init(a, 6);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(0, 2, 1);
    try g.addEdge(1, 3, 1);
    try g.addEdge(2, 3, 1);
    try g.addEdge(4, 5, 1); // separate component, unreachable from 0
    const order = try g.bfs(0);
    defer a.free(order);
    try expectEqualSlices(usize, &.{ 0, 1, 2, 3 }, order);
}

test "graph: dfs marks exactly the reachable set" {
    const a = testing.allocator;
    var g = try Graph.init(a, 6);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(0, 2, 1);
    try g.addEdge(1, 3, 1);
    try g.addEdge(2, 3, 1);
    try g.addEdge(4, 5, 1);
    const visited = try a.alloc(bool, 6);
    defer a.free(visited);
    for (visited) |*v| v.* = false;
    g.dfs(0, visited);
    try expectEqualSlices(bool, &.{ true, true, true, true, false, false }, visited);
}

test "graph: dfs terminates on a cycle" {
    const a = testing.allocator;
    var g = try Graph.init(a, 3);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(1, 2, 1);
    try g.addEdge(2, 0, 1); // cycle: must not loop forever
    const visited = try a.alloc(bool, 3);
    defer a.free(visited);
    for (visited) |*v| v.* = false;
    g.dfs(0, visited);
    try expectEqualSlices(bool, &.{ true, true, true }, visited);
}

test "graph: topological sort of a DAG respects every edge" {
    const a = testing.allocator;
    var g = try Graph.init(a, 6);
    defer g.deinit();
    try g.addEdge(5, 2, 1);
    try g.addEdge(5, 0, 1);
    try g.addEdge(4, 0, 1);
    try g.addEdge(4, 1, 1);
    try g.addEdge(2, 3, 1);
    try g.addEdge(3, 1, 1);
    const order = try g.topologicalSort();
    defer a.free(order);
    try assertValidTopo(&g, order);
}

test "graph: topological sort across disconnected DAGs" {
    const a = testing.allocator;
    var g = try Graph.init(a, 4);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(2, 3, 1); // two independent chains
    const order = try g.topologicalSort();
    defer a.free(order);
    try assertValidTopo(&g, order);
}

test "graph: topological sort detects a cycle" {
    const a = testing.allocator;
    var g = try Graph.init(a, 3);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(1, 2, 1);
    try g.addEdge(2, 0, 1);
    try expectError(error.CycleError, g.topologicalSort());
}

test "graph: dijkstra shortest paths from source 0" {
    const a = testing.allocator;
    var g = try Graph.init(a, 5);
    defer g.deinit();
    try g.addEdge(0, 1, 10);
    try g.addEdge(0, 2, 3);
    try g.addEdge(2, 1, 4); // 0->2->1 = 7 beats the direct 0->1 = 10
    try g.addEdge(1, 3, 2);
    try g.addEdge(2, 3, 8); // 0->2->1->3 = 9 beats 0->2->3 = 11
    try g.addEdge(3, 4, 5);
    const dist = try g.dijikstra(0);
    defer a.free(dist);
    try expectEqualSlices(u64, &.{ 0, 7, 3, 9, 14 }, dist);
}

test "graph: dijkstra marks unreachable nodes as INF" {
    const a = testing.allocator;
    var g = try Graph.init(a, 4);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(1, 2, 1);
    // node 3 has no incoming edges -> unreachable from 0
    const dist = try g.dijikstra(0);
    defer a.free(dist);
    try expectEqualSlices(u64, &.{ 0, 1, 2, INF }, dist);
}

// Catches a source seeded as a hardcoded 0 instead of `src`.
test "graph: dijkstra from a non-zero source" {
    const a = testing.allocator;
    var g = try Graph.init(a, 5);
    defer g.deinit();
    try g.addEdge(0, 1, 10);
    try g.addEdge(0, 2, 3);
    try g.addEdge(2, 1, 4);
    try g.addEdge(1, 3, 2);
    try g.addEdge(2, 3, 8);
    try g.addEdge(3, 4, 5);
    const dist = try g.dijikstra(2); // node 0 is unreachable from 2 (directed)
    defer a.free(dist);
    try expectEqualSlices(u64, &.{ INF, 4, 0, 6, 11 }, dist);
}

test "graph: dijkstra single node" {
    const a = testing.allocator;
    var g = try Graph.init(a, 1);
    defer g.deinit();
    const dist = try g.dijikstra(0);
    defer a.free(dist);
    try expectEqualSlices(u64, &.{0}, dist);
}

// A node reachable two ways; the heap must surface the cheaper route first.
test "graph: dijkstra prefers the cheaper of two routes" {
    const a = testing.allocator;
    var g = try Graph.init(a, 4);
    defer g.deinit();
    try g.addEdge(0, 1, 1);
    try g.addEdge(0, 2, 5);
    try g.addEdge(1, 2, 1); // 0->1->2 = 2 beats the direct 0->2 = 5
    try g.addEdge(2, 3, 1);
    const dist = try g.dijikstra(0);
    defer a.free(dist);
    try expectEqualSlices(u64, &.{ 0, 1, 2, 3 }, dist);
}
