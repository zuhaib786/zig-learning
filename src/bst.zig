const std = @import("std");
const Allocator = std.mem.Allocator;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

fn lessThanU32(a: u32, b: u32) bool {
    return a < b;
}

// Helper: build a tree from a slice. Caller deinits.
fn buildTree(a: Allocator, values: []const u32) !BST(u32) {
    var tree = BST(u32).init(a, lessThanU32);
    errdefer tree.deinit();
    for (values) |v| try tree.insert(v);
    return tree;
}

pub fn BST(comptime T: type) type {
    return struct {
        const Self = @This();
        const Node = struct { value: T, left: ?*Node, right: ?*Node };

        root: ?*Node = null,
        len: usize = 0,
        allocator: Allocator,
        lessThan: *const fn (T, T) bool,

        fn init(allocator: Allocator, lessThan: *const fn (T, T) bool) Self {
            return .{
                .allocator = allocator,
                .lessThan = lessThan,
            };
        }

        pub fn insert(self: *Self, value: T) !void {
            self.root = try self._insert(value, self.root);
        }
        fn _insert(self: *Self, value: T, node: ?*Node) !*Node {
            const n = node orelse try self.makeNode(value);
            if (self.lessThan(value, n.value)) {
                n.left = try self._insert(value, n.left);
            } else if (self.lessThan(n.value, value)) {
                n.right = try self._insert(value, n.right);
            }
            return n;
        }

        pub fn contains(self: *Self, value: T) bool {
            return self._contains(value, self.root);
        }
        fn _contains(self: *Self, value: T, node: ?*Node) bool {
            const n = node orelse return false;
            if (self.lessThan(n.value, value)) return self._contains(value, n.right);
            if (self.lessThan(value, n.value)) return self._contains(value, n.left);
            return true;
        }

        pub fn inOrder(self: *Self, allocator: Allocator) ![]T {
            var list: std.ArrayList(T) = .empty;
            errdefer list.deinit(allocator);
            try self._inOrder(self.root, &list, allocator);
            return list.toOwnedSlice(allocator);
        }

        pub fn _inOrder(self: *Self, node: ?*Node, list: *std.ArrayList(T), allocator: Allocator) !void {
            const n = node orelse return;
            try self._inOrder(n.left, list, allocator);
            try list.append(allocator, n.value);
            try self._inOrder(n.right, list, allocator);
        }

        pub fn min(self: *Self) ?T {
            var ans: ?T = null;
            var node = self.root;
            while (node) |n| {
                ans = n.value;
                node = n.left;
            }
            return ans;
        }
        pub fn max(self: *Self) ?T {
            var ans: ?T = null;
            var node = self.root;
            while (node) |n| {
                ans = n.value;
                node = n.right;
            }
            return ans;
        }
        pub fn delete(self: *Self, value: T) bool {
            const sz = self.len;
            self.root = self._delete(value, self.root);
            return sz > self.len;
        }
        fn _delete(self: *Self, value: T, node: ?*Node) ?*Node {
            const n = node orelse return null;
            if (self.lessThan(value, n.value)) {
                n.left = self._delete(value, n.left);
                return n;
            }
            if (self.lessThan(n.value, value)) {
                n.right = self._delete(value, n.right);
                return n;
            }
            // found n;
            if (n.left == null) {
                const r = n.right;
                self.deleteNode(n);
                return r;
            }
            if (n.right == null) {
                const l = n.left;
                self.deleteNode(n);
                return l;
            }
            const succ = minNode(n.right.?);
            n.value = succ.value;
            n.right = self._delete(succ.value, n.right);
            return n;
        }

        pub fn deinit(self: *Self) void {
            self._destroy(self.root);
            self.root = null;
            self.len = 0;
        }
        fn _destroy(self: *Self, node: ?*Node) void {
            const n = node orelse return;
            if (n.left) |l| {
                self._destroy(l);
            }
            if (n.right) |r| {
                self._destroy(r);
            }
            self.deleteNode(n);
        }

        fn minNode(node: *Node) *Node {
            var trav = node;
            while (trav.left) |left_node| {
                trav = left_node;
            }
            return trav;
        }

        fn makeNode(self: *Self, value: T) !*Node {
            const node = try self.allocator.create(Node);
            node.left = null;
            node.right = null;
            node.value = value;
            self.len += 1;
            return node;
        }

        fn deleteNode(self: *Self, node: *Node) void {
            self.allocator.destroy(node);
            self.len -= 1;
        }
    };
}
test "bst: in-order traversal is sorted (and ignores duplicates)" {
    const a = std.testing.allocator;
    var tree = try buildTree(a, &.{ 50, 30, 70, 20, 40, 60, 80, 30 }); // 30 inserted twice
    defer tree.deinit();
    const out = try tree.inOrder(a);
    defer a.free(out);
    try expectEqualSlices(u32, &.{ 20, 30, 40, 50, 60, 70, 80 }, out);
}

test "bst: contains, min, max" {
    const a = std.testing.allocator;
    var tree = try buildTree(a, &.{ 50, 30, 70, 20, 40, 60, 80 });
    defer tree.deinit();
    try expect(tree.contains(40));
    try expect(tree.contains(80));
    try expect(!tree.contains(99));
    try expectEqual(@as(u32, 20), tree.min().?);
    try expectEqual(@as(u32, 80), tree.max().?);

    var empty = BST(u32).init(a, lessThanU32);
    defer empty.deinit();
    try expect(empty.min() == null);
    try expect(empty.max() == null);
    try expect(!empty.contains(1));
}

test "bst: delete a leaf" {
    const a = std.testing.allocator;
    var tree = try buildTree(a, &.{ 50, 30, 70, 20, 40 });
    defer tree.deinit();
    try expect(tree.delete(20)); // 20 is a leaf
    try expect(!tree.contains(20));
    const out = try tree.inOrder(a);
    defer a.free(out);
    try expectEqualSlices(u32, &.{ 30, 40, 50, 70 }, out);
}

test "bst: delete a node with one child" {
    const a = std.testing.allocator;
    // 70 has only a left child (60)
    var tree = try buildTree(a, &.{ 50, 30, 70, 60 });
    defer tree.deinit();
    try expect(tree.delete(70));
    try expect(!tree.contains(70));
    const out = try tree.inOrder(a);
    defer a.free(out);
    try expectEqualSlices(u32, &.{ 30, 50, 60 }, out); // 60 took 70's place
}

test "bst: delete a node with two children (uses successor)" {
    const a = std.testing.allocator;
    var tree = try buildTree(a, &.{ 50, 30, 70, 20, 40, 60, 80 });
    defer tree.deinit();
    try expect(tree.delete(30)); // two children (20, 40); successor is 40
    try expect(!tree.contains(30));
    const out = try tree.inOrder(a);
    defer a.free(out);
    try expectEqualSlices(u32, &.{ 20, 40, 50, 60, 70, 80 }, out);
}

test "bst: delete the root (two children)" {
    const a = std.testing.allocator;
    var tree = try buildTree(a, &.{ 50, 30, 70, 20, 40, 60, 80 });
    defer tree.deinit();
    try expect(tree.delete(50)); // root; successor is 60
    try expect(!tree.contains(50));
    const out = try tree.inOrder(a);
    defer a.free(out);
    try expectEqualSlices(u32, &.{ 20, 30, 40, 60, 70, 80 }, out);
}

test "bst: delete down to empty, and delete-missing returns false" {
    const a = std.testing.allocator;
    var tree = try buildTree(a, &.{ 50, 30, 70 });
    defer tree.deinit();
    try expect(!tree.delete(999)); // absent → false, tree unchanged
    try expect(tree.delete(50));
    try expect(tree.delete(30));
    try expect(tree.delete(70));
    const out = try tree.inOrder(a);
    defer a.free(out);
    try expectEqualSlices(u32, &.{}, out);
    try expect(tree.min() == null);
}

