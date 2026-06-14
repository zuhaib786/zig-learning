//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub const basics = @import("basics.zig");
pub const strings = @import("strings.zig");
pub const freq = @import("freq.zig");
pub const list = @import("list.zig");
pub const queue = @import("queue.zig");
pub const lru = @import("lru.zig");
pub const sort = @import("sort.zig");
pub const bst = @import("bst.zig");

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    std.testing.refAllDecls(@This());
}
