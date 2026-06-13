const std = @import("std");
const Io = std.Io;

const lzig = @import("lzig");
// TODO: Implement these functions

//   1. add(a: i32, b: i32) i32
//   2. min(a: i32, b: i32) i32
//   3. max(a: i32, b: i32) i32
//   4. clamp(value: i32, low: i32, high: i32) i32
//   5. factorial(n: u8) u64
//   6. fibonacci(n: u8) u64
//   7. stringLength(s: []const u8) usize
//   8. findFirstEven(values: []const i32) ?i32
//  9. safeDivide(a: i32, b: i32) !i32

pub fn genericAdd(T: type, a: T, b: T) T {
    return a + b;
}

pub fn genericMin(T: type, a: T, b: T) T {
    if (a < b) return a;
    return b;
}
pub fn genericMax(T: type, a: T, b: T) T {
    if (a > b) return a;
    return b;
}

pub fn min(a: i32, b: i32) i32 {
    return genericMin(i32, a, b);
}

pub fn max(a: i32, b: i32) i32 {
    return genericMax(i32, a, b);
}
pub fn clamp(value: i32, low: i32, high: i32) i32 {
    if (value >= low and value <= high) return value;
    if (value < low) return low;
    return high;
}

pub fn factorial(n: u8) u64 {
    var ans: u64 = 1;
    var i: u8 = 1;
    while (i <= n) : (i += 1) {
        ans = ans * i;
    }
    return ans;
}

pub fn fibonacci(n: u8) u64 {
    var prev1: u64 = 0;
    var prev2: u64 = 1;
    var cur: u64 = 1;
    if (n == 0) return 0;
    if (n == 1) return 1;
    for (1..n) |_| {
        cur = prev1 + prev2;
        prev1 = prev2;
        prev2 = cur;
    }
    return cur;
}

const MathError = error{DivisionByZero};

pub fn safeDivide(a: i32, b: i32) MathError!i32 {
    return switch (b) {
        0 => MathError.DivisionByZero,
        else => @divFloor(a, b),
    };
}

pub fn stringLength(s: []const u8) usize {
    return s.len;
}

pub fn findFirstEven(values: []const i32) ?i32 {
    for (values) |value| {
        if (@mod(value, 2) == 0) return value;
    }
    return null;
}

test "generic Min works for all" {
    const a_i: i32 = 10;
    const b_i: i32 = 20;
    const a_u: u32 = 10;
    const b_u: u32 = 20;
    const a_f: f32 = 10.2;
    const b_f: f32 = 20.0;
    try std.testing.expectEqual(10, genericMin(i32, a_i, b_i));
    try std.testing.expectEqual(10, genericMin(u32, a_u, b_u));
    try std.testing.expectEqual(10.2, genericMin(f32, a_f, b_f));
}
test "generic Max works for all" {
    const a_i: i32 = 10;
    const b_i: i32 = 20;
    const a_u: u32 = 10;
    const b_u: u32 = 20;
    const a_f: f32 = 10.2;
    const b_f: f32 = 20.0;
    try std.testing.expectEqual(20, genericMax(i32, a_i, b_i));
    try std.testing.expectEqual(20, genericMax(u32, a_u, b_u));
    try std.testing.expectEqual(20.0, genericMax(f32, a_f, b_f));
}

test "clamp" {
    const low: i32 = 20;
    const high: i32 = 100;
    try std.testing.expectEqual(30, clamp(30, low, high));
    try std.testing.expectEqual(20, clamp(20, low, high));
    try std.testing.expectEqual(100, clamp(100, low, high));
    try std.testing.expectEqual(20, clamp(10, low, high));
    try std.testing.expectEqual(100, clamp(1000, low, high));
}

test "factorial" {
    try std.testing.expectEqual(120, factorial(5));
    try std.testing.expectEqual(1, factorial(0));
    try std.testing.expectEqual(1, factorial(1));
    try std.testing.expectEqual(720, factorial(6));
    try std.testing.expectEqual(factorial(10), 10 * factorial(9));
    try std.testing.expectEqual(factorial(20), 20 * factorial(19));
}

test "safe divide" {
    try std.testing.expectEqual(12, try safeDivide(120, 10));
    try std.testing.expectError(MathError.DivisionByZero, safeDivide(129, 0));
    try std.testing.expectEqual(17, safeDivide(35, 2));
    try std.testing.expectEqual(-18, safeDivide(-35, 2)); // Purposefully not unwrapped to prove that erorr union checks do not need explicit unwrapping
}

test "string length" {
    try std.testing.expectEqual(6, stringLength("Zuhaib"));
    try std.testing.expectEqual(9, stringLength("Zuhaib Ul"));
    try std.testing.expectEqual(16, stringLength("Zuhaib Ul Zamann"));
}

test "find first even" {
    try std.testing.expectEqual(10, findFirstEven(([_]i32{ 10, 20, 30 })[0..]));
    try std.testing.expectEqual(20, findFirstEven(([_]i32{ 7, 20, 30 })[0..]));
    try std.testing.expectEqual(null, findFirstEven(([_]i32{ 7, 21, 33 })[0..]));
}

test "fibonacci" {
    try std.testing.expectEqual(0, fibonacci(0));
    try std.testing.expectEqual(1, fibonacci(1));
    try std.testing.expectEqual(1, fibonacci(2));
    try std.testing.expectEqual(fibonacci(10) + fibonacci(11), fibonacci(12));
}
