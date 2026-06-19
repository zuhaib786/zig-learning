const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Record = struct {
    key: []const u8,
    value: u32,
};
const MAGIC = "LZIG";
const VERSION: u16 = 1;

pub fn writeRecords(writer: *std.Io.Writer, records: []const Record) !void {
    try writer.writeAll(MAGIC);
    try writer.writeInt(u16, VERSION, .little);
    try writer.writeInt(u32, @intCast(records.len), .little);
    for (records) |record| {
        try writer.writeInt(u32, @intCast(record.key.len), .little);
        try writer.writeAll(record.key);
        try writer.writeInt(u32, record.value, .little);
    }
}

fn freeRecords(allocator: Allocator, records: []Record) void {
    for (records) |record| {
        allocator.free(record.key);
    }
    allocator.free(records);
}

pub fn readRecords(allocator: Allocator, reader: *std.Io.Reader) ![]Record {
    const magic = try reader.takeArray(4);
    if (!std.mem.eql(u8, magic, MAGIC)) return error.BadMagic;
    const version = try reader.takeInt(u16, .little);
    if (version != VERSION) return error.UnsupportedVersion;
    const count = try reader.takeInt(u32, .little);
    var records = try allocator.alloc(Record, count);
    errdefer allocator.free(records);
    var filled: usize = 0;
    errdefer for (records[0..filled]) |record| allocator.free(record.key);
    while (filled < count) : (filled += 1) {
        const key_len = try reader.takeInt(u32, .little);
        const key = try allocator.alloc(u8, key_len);
        errdefer allocator.free(key);
        try reader.readSliceAll(key);
        const value = try reader.takeInt(u32, .little);
        records[filled] = .{ .key = key, .value = value };
    }
    return records;
}

test "identity property" {
    const allocator = std.testing.allocator;
    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    var reader = std.Io.Reader.fixed(&buf);
    const records: [3]Record = .{ .{ .key = "Zuhaib", .value = 10 }, .{ .key = "Zig", .value = 20 }, .{ .key = "Zamann", .value = 10 } };
    try writeRecords(&writer, &records);
    try writer.flush();
    const found_records = try readRecords(allocator, &reader);
    defer freeRecords(allocator, found_records);
    try std.testing.expectEqual(records.len, found_records.len);
    for (records, found_records) |record, found_record| {
        try std.testing.expect(std.mem.eql(u8, record.key, found_record.key));
        try std.testing.expectEqual(record.value, found_record.value);
    }
}
test "bad magic" {
    const allocator = std.testing.allocator;
    const text = "XXXX";
    var reader = std.Io.Reader.fixed(text);
    const records = readRecords(allocator, &reader);
    try std.testing.expectError(error.BadMagic, records);
}
test "bad version" {
    const allocator = std.testing.allocator;
    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try writer.writeAll(MAGIC);
    try writer.writeInt(u16, 2, .little);
    try writer.flush();
    var reader = std.Io.Reader.fixed(&buf);
    const found_records = readRecords(allocator, &reader);
    try std.testing.expectError(error.UnsupportedVersion, found_records);
}

test "truncated file" {
    const allocator = std.testing.allocator;
    var buf: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try writer.writeAll(MAGIC);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 2, .little);
    try writer.writeInt(u32, @intCast("Zuhaib".len), .little);
    try writer.writeAll("Zuhaib");
    try writer.writeInt(u32, 10, .little);
    try writer.flush();
    var reader = std.Io.Reader.fixed(&buf);
    const found_records = readRecords(allocator, &reader);
    try std.testing.expectError(error.EndOfStream, found_records);
}
