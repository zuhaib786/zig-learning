const std = @import("std");
const Io = std.Io;

const Allocator = std.mem.Allocator;

/// Caller owns the returned slice; free it with the same allocator.
pub fn dup(allocator: Allocator, s: []const u8) ![]u8 {
    const n = s.len;
    const out = try allocator.alloc(u8, n);
    @memcpy(out, s);
    return out;
}

/// Caller owns the returned slice; free it with the same allocator.
pub fn reverse(allocator: Allocator, s: []const u8) ![]u8 {
    const n = s.len;
    const out = try allocator.alloc(u8, n);
    for (0..n) |i| {
        out[i] = s[n - 1 - i];
    }
    return out;
}
pub fn join(allocator: Allocator, parts: []const []const u8, sep: []const u8) ![]u8 {
    var length: usize = 0;
    for (parts) |part| {
        length += part.len;
    }
    if (parts.len > 0) length += sep.len * (parts.len - 1);
    const out = try allocator.alloc(u8, length);
    if (parts.len == 0) return out;
    var offset: usize = 0;
    for (parts[0 .. parts.len - 1]) |part| {
        @memcpy(out[offset .. offset + part.len], part);
        offset += part.len;
        @memcpy(out[offset .. offset + sep.len], sep);
        offset += sep.len;
    }
    @memcpy(out[offset .. offset + parts[parts.len - 1].len], parts[parts.len - 1]);
    return out;
}

/// Caller owns the returned outer slice and must free it with the same
/// allocator. The inner slices are views INTO `s` — do not free them
/// individually, and they are only valid as long as `s` lives.
pub fn split(allocator: Allocator, s: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);
    var start: usize = 0;
    for (s, 0..s.len) |c, i| {
        if (c == ',') {
            try list.append(allocator, s[start..i]);
            start = i + 1;
        }
    }
    try list.append(allocator, s[start..]);
    return list.toOwnedSlice(allocator);
}

const StringBuilder = struct {
    buf: []u8 = &.{},
    len: usize = 0,

    pub fn append(self: *StringBuilder, allocator: Allocator, bytes: []const u8) !void {
        const needed = self.len + bytes.len;
        if (needed > self.buf.len) {
            const new_cap = @max(needed, 2 * self.buf.len);
            self.buf = try allocator.realloc(self.buf, new_cap);
        }
        @memcpy(self.buf[self.len..needed], bytes);
        self.len = needed;
    }

    pub fn toOwnedSlice(self: *StringBuilder, allocator: Allocator) ![]u8 {
        const out = try allocator.realloc(self.buf, self.len);
        self.buf = &.{};
        self.len = 0;
        return out;
    }

    pub fn deinit(self: *StringBuilder, allocator: Allocator) void {
        allocator.free(self.buf);
        self.* = .{};
    }
};

test "dup works" {
    const s: []const u8 = "Hello";
    const allocator = std.testing.allocator;
    const out = try dup(allocator, s);
    defer allocator.free(out); // commenting out causes error;
    try std.testing.expectEqualStrings(s, out);
    try std.testing.expect(s.ptr != out.ptr);
}

test "reverse works" {
    const s: []const u8 = "Hello";
    const allocator = std.testing.allocator;
    const out = try reverse(allocator, s);
    defer allocator.free(out); // commenting out causes error Prints 1 tests leaked memory ...;
    try std.testing.expectEqualStrings("olleH", out);
    try std.testing.expect(s.ptr != out.ptr);
}

test "join works" {
    const parts: []const []const u8 = &[_][]const u8{ "all", "is", "well" };
    const sep = ",";
    const allocator = std.testing.allocator;
    const out = try join(allocator, parts, sep);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("all,is,well", out);
}
test "join works for singleton" {
    const parts: []const []const u8 = &[_][]const u8{"all"};
    const sep = ",";
    const allocator = std.testing.allocator;
    const out = try join(allocator, parts, sep);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("all", out);
}

test "join works for empty" {
    const parts: []const []const u8 = &[_][]const u8{};
    const sep = ",";
    const allocator = std.testing.allocator;
    const out = try join(allocator, parts, sep);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("", out);
}
test "split works" {
    const s = "a,b,c";
    const allocator = std.testing.allocator;
    const out = try split(allocator, s);
    defer allocator.free(out);
    try std.testing.expectEqual(3, out.len);
    try std.testing.expectEqualStrings("a", out[0]);
    try std.testing.expectEqualStrings("b", out[1]);
    try std.testing.expectEqualStrings("c", out[2]);
}
test "split works for cons delim" {
    const s = "a,,c";
    const allocator = std.testing.allocator;
    const out = try split(allocator, s);
    defer allocator.free(out);
    try std.testing.expectEqual(3, out.len);
    try std.testing.expectEqualStrings("a", out[0]);
    try std.testing.expectEqualStrings("", out[1]);
    try std.testing.expectEqualStrings("c", out[2]);
}
test "split works for no delim" {
    const s = "abc";
    const allocator = std.testing.allocator;
    const out = try split(allocator, s);
    defer allocator.free(out);
    try std.testing.expectEqual(1, out.len);
    try std.testing.expectEqualStrings("abc", out[0]);
}

test "string builder implementation" {
    const allocator = std.testing.allocator;
    var sb: StringBuilder = .{};
    defer sb.deinit(allocator);
    try sb.append(allocator, "Hello ");
    try sb.append(allocator, "World");
    const out = try sb.toOwnedSlice(allocator);
    defer allocator.free(out); // Should free the slice and the deinit will be called. Looks virtuall double free but isnt. Should be fine
    try std.testing.expectEqualStrings("Hello World", out);
}
test "string builder empty string" {
    const allocator = std.testing.allocator;
    var sb: StringBuilder = .{};
    defer sb.deinit(allocator);
    try sb.append(allocator, "");
    const out = try sb.toOwnedSlice(allocator);
    defer allocator.free(out); // Should be freeable even if empty
    try std.testing.expectEqualStrings("", out);
}

test "string builder looped" {
    const allocator = std.testing.allocator;
    var sb: StringBuilder = .{};
    defer sb.deinit(allocator);
    for (0..100) |i| {
        if (@mod(i, 2) == 0) try sb.append(allocator, "Hello ");
        if (@mod(i, 2) == 1) try sb.append(allocator, "World");
    }
    const out = try sb.toOwnedSlice(allocator);
    defer allocator.free(out); // Should be freeable even if empty
    try std.testing.expectEqualStrings(&("Hello World".* ** 50), out);
}
