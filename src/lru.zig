const std = @import("std");
const strings = @import("strings.zig");
const Allocator = std.mem.Allocator;

pub fn LruCache(comptime V: type) type {
    return struct {
        const Self = @This();
        const Node = struct { key: []const u8, prev: ?*Node, next: ?*Node, value: V };

        allocator: Allocator,
        map: std.StringHashMap(*Node),
        head: ?*Node = null,
        tail: ?*Node = null,
        capacity: usize = 0,

        pub fn init(allocator: Allocator, capacity: usize) Self {
            return .{
                .allocator = allocator,
                .capacity = capacity,
                .map = .init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // destroy map first. Keys are owwned by nodes. So dont deinit them yet
            self.map.deinit();
            // destroy linked list
            while (self.head) |head| {
                const next = head.next;
                // Values are not owned. So we dont destroy them;
                // Now destroy the node
                self.freeNode(head);
                // update the head
                self.head = next;
            }
            self.capacity = 0;
        }

        pub fn evict(self: *Self) void {
            // check if tail is null
            if (self.tail == null) return;
            const new_tail = self.tail.?.prev;
            const tail = self.tail.?;
            self.detatch(tail);
            _ = self.map.remove(tail.key);
            self.freeNode(tail);
            if (new_tail == null) {
                self.head = null;
            }
            self.tail = new_tail;
        }

        pub fn get(self: *Self, key: []const u8) ?V {
            if (self.map.get(key)) |node| {

                // Key is already present. It is now MRU
                self.detatch(node);
                self.pushFront(node);
                return node.value;
            }
            return null;
        }

        pub fn put(self: *Self, key: []const u8, value: V) !void {
            if (self.map.get(key)) |node| {
                node.value = value;
                self.detatch(node);
                self.pushFront(node);
                return;
            }
            // Key is absent
            if (self.map.count() == self.capacity) {
                self.evict();
            }
            const node = try self.allocator.create(Node);
            node.key = try strings.dup(self.allocator, key);
            node.value = value;
            node.next = null;
            node.prev = null;
            self.pushFront(node);
            try self.map.put(node.key, node);
        }

        fn detatch(self: *Self, node: *Node) void {
            if (self.head) |head| {
                if (head == node) {
                    self.head = head.next;
                }
            }
            if (self.tail) |tail| {
                if (tail == node) {
                    self.tail = tail.prev;
                }
            }
            if (node.prev) |prev| {
                prev.next = node.next;
            }
            if (node.next) |next| {
                next.prev = node.prev;
            }
            node.prev = null;
            node.next = null;
        }

        fn freeNode(self: *Self, node: *Node) void {
            // delete key first
            self.allocator.free(node.key);
            // delete the noe no
            self.allocator.destroy(node);
        }

        fn pushFront(self: *Self, node: *Node) void {
            if (self.head) |head| {
                head.prev = node;
                node.next = head;
                self.head = node;
            } else {
                self.head = node;
                self.tail = node;
            }
        }
    };
}

test "LRU cache implementation" {
    const allocator = std.testing.allocator;
    var cache: LruCache([]const u8) = .init(allocator, 3);
    defer cache.deinit(); // Necessary.
    try cache.put("Zuhaib", "Loves Zig");
    try cache.put("Random Guy", "Loves Zig generally");
    try cache.put("Jarred", "Hates Zig");
    try std.testing.expectEqualStrings("Loves Zig", cache.get("Zuhaib").?);
    try cache.put("WHo doesnt", "Love Zig");
    try std.testing.expect(cache.get("Random Guy") == null);
}
