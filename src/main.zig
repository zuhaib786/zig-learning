const std = @import("std");
const freq = @import("freq.zig");
const Io = std.Io;

const CliError = error{
    MissingCommand,
    UnknownCommand,
};

const CountResult = struct {
    args: usize,
    bytes: usize,
};

const TextCount = struct {
    bytes: usize = 0,
    lines: usize = 0,
    words: usize = 0,
};

const Command = enum {
    echo,
    count,
    cat,
    copy,
    freq,
};

const Counter = struct {
    count: TextCount = .{},
    in_word: bool = false,

    fn feed(self: *Counter, input: []const u8) void {
        self.count.bytes += input.len;
        for (input) |byte| {
            if (byte == '\n') {
                self.count.lines += 1;
            }
            if (byte == '\n' or byte == ' ' or byte == '\t' or byte == '\r') {
                if (self.in_word) {
                    self.count.words += 1;
                }
                self.in_word = false;
            } else {
                self.in_word = true;
            }
        }
    }

    fn finish(self: *Counter) TextCount {
        if (self.in_word) {
            self.count.words += 1;
        }
        return self.count;
    }
};

fn printOpenError(err: *std.Io.Writer, path: []const u8, e: anyerror) !void {
    switch (e) {
        error.FileNotFound => try err.print("{s}: no such file\n", .{path}),
        error.AccessDenied => try err.print("{s}: permission denied\n", .{path}),
        error.IsDir => try err.print("{s}: is a directory\n", .{path}),
        else => try err.print("{s}: cannot open\n", .{path}),
    }
}

pub fn parseCommand(command_str: []const u8) ?Command {
    if (std.mem.eql(u8, command_str, "echo")) return .echo;
    if (std.mem.eql(u8, command_str, "count")) return .count;
    if (std.mem.eql(u8, command_str, "cat")) return .cat;
    if (std.mem.eql(u8, command_str, "copy")) return .copy;
    if (std.mem.eql(u8, command_str, "freq")) return .freq;
    return null;
}

pub fn addArgToCount(count: *CountResult, arg: []const u8) void {
    count.args += 1;
    count.bytes += arg.len;
}

pub fn handle_echo(args: *std.process.Args.Iterator, stdout: *std.Io.Writer) !bool {
    var first = true;
    while (args.next()) |arg| {
        if (!first) try stdout.print(" ", .{});
        try stdout.print("{s}", .{arg});
        first = false;
    }
    try stdout.print("\n", .{});
    return true;
}

pub fn count_from_reader(out: *std.Io.Writer, reader: *std.Io.Reader) !void {
    var chunk: [1024]u8 = undefined;
    var counter: Counter = .{};
    while (true) {
        const n = try reader.readSliceShort(&chunk);
        if (n == 0) break;
        counter.feed(chunk[0..n]);
    }
    const result = counter.finish();
    try out.print("Bytes: {d}\nLines: {d}\nWords: {d}\n", .{ result.bytes, result.lines, result.words });
}
pub fn countText(input: []const u8) TextCount {
    var c: Counter = .{};
    c.feed(input);
    return c.finish();
}

pub fn handle_count(args: *std.process.Args.Iterator, out: *std.Io.Writer, err: *std.Io.Writer, in: *std.Io.Reader, io: std.Io) !bool {
    const path = args.next() orelse {
        try count_from_reader(out, in);
        return true;
    };
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |e| {
        try printOpenError(err, path, e);
        return false;
    };
    defer file.close(io);
    var buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    const reader = &file_reader.interface;
    try count_from_reader(out, reader);
    return true;
}

pub fn handle_cat(args: *std.process.Args.Iterator, out: *std.Io.Writer, err: *std.Io.Writer, io: std.Io) !bool {
    const path: []const u8 = args.next() orelse {
        try err.print("cat: missing path\n", .{});
        return false;
    };
    const file = std.Io.Dir.cwd().openFile(io, path, .{}) catch |e| {
        try printOpenError(err, path, e);
        return false;
    };
    defer file.close(io);
    var buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buf);
    const reader = &file_reader.interface;
    _ = try reader.streamRemaining(out);
    return true;
}

pub fn handle_copy(args: *std.process.Args.Iterator, out: *std.Io.Writer, err: *std.Io.Writer, io: std.Io) !bool {
    const src = args.next() orelse {
        try err.print("Please provide src and destination files\n", .{});
        return false;
    };
    const dst = args.next() orelse {
        try err.print("Please provide destination file\n", .{});
        return false;
    };
    const src_file = std.Io.Dir.cwd().openFile(io, src, .{}) catch |e| {
        try printOpenError(err, src, e);
        return false;
    };
    defer src_file.close(io);
    var reader_buf: [1024]u8 = undefined;
    var file_reader = src_file.reader(io, &reader_buf);
    const reader = &file_reader.interface;

    const dst_file = std.Io.Dir.cwd().createFile(io, dst, .{}) catch |e| {
        try printOpenError(err, dst, e);
        return false;
    };
    defer dst_file.close(io);
    var writer_buf: [1024]u8 = undefined;
    var file_writer = dst_file.writer(io, &writer_buf);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};
    const n = try reader.streamRemaining(writer);
    try out.print("Copied {d} bytes successfully from {s} to {s}\n", .{ n, src, dst });
    return true;
}

pub fn handle_freq(args: *std.process.Args.Iterator, out: *std.Io.Writer, in: *std.Io.Reader, io: std.Io, gpa: std.mem.Allocator) !bool {
    _ = io;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = try in.allocRemaining(allocator, .unlimited);
    const k_str = args.next() orelse "10";
    const k = try std.fmt.parseInt(usize, k_str, 10);
    const word_map = try freq.countWords(allocator, text);
    const top_k = try freq.topK(allocator, word_map, k);

    for (top_k) |word_count| {
        try out.print("{s}: {d}\n", .{ word_count.word, word_count.count });
    }
    return true;
}

pub fn countArgs(args: []const []const u8) CountResult {
    var count_result: CountResult = .{ .args = 0, .bytes = 0 };
    for (args) |arg| {
        addArgToCount(&count_result, arg);
    }
    return count_result;
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    const io = init.io;
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buffer);
    const stdout = &stdout_writer.interface;
    var std_err_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &std_err_buffer);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};
    defer stdout.flush() catch {};
    const stdin_file = std.Io.File.stdin();
    var stdin_buffer: [4096]u8 = undefined;
    var stdin_reader = stdin_file.reader(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;

    _ = args.next(); // Skip what is at start
    const usage: []const u8 =
        \\usage: lzig <command> [args]
        \\commands: echo count cat copy freq
        \\
    ;
    const command_name: []const u8 = args.next() orelse {
        try stderr.print(usage, .{});
        return CliError.MissingCommand;
    };

    const command = parseCommand(command_name) orelse {
        try stderr.print("unknown command: {s}\n", .{command_name});
        return CliError.UnknownCommand;
    };
    const ok = switch (command) {
        .echo => try handle_echo(&args, stdout),
        .count => try handle_count(&args, stdout, stderr, stdin, io),
        .cat => try handle_cat(&args, stdout, stderr, io),
        .copy => try handle_copy(&args, stdout, stderr, io),
        .freq => try handle_freq(&args, stdout, stdin, io, init.gpa),
    };
    if (!ok) {
        // process.exit() skips the deferred flushes above, so flush by hand first.
        stdout.flush() catch {};
        stderr.flush() catch {};
        std.process.exit(1);
    }
}

test "add arg to count" {
    var count_result: CountResult = .{ .args = 0, .bytes = 0 };
    addArgToCount(&count_result, "Hello");
    try std.testing.expectEqual(5, count_result.bytes);
    try std.testing.expectEqual(1, count_result.args);

    addArgToCount(&count_result, "World");
    try std.testing.expectEqual(10, count_result.bytes);
    try std.testing.expectEqual(2, count_result.args);
}
test "parse command" {
    try std.testing.expectEqual(Command.echo, parseCommand("echo").?);
    try std.testing.expectEqual(Command.count, parseCommand("count").?);
    try std.testing.expectEqual(null, parseCommand("nope"));
}
test "text count" {
    var text: []const u8 = "";
    var text_count = countText(text);
    try std.testing.expectEqual(TextCount{ .bytes = 0, .lines = 0, .words = 0 }, text_count);
    text = "hello";
    text_count = countText(text);
    try std.testing.expectEqual(TextCount{ .lines = 0, .words = 1, .bytes = 5 }, text_count);

    text = "hello\nzig\n";
    text_count = countText(text);
    try std.testing.expectEqual(TextCount{ .lines = 2, .words = 2, .bytes = 10 }, text_count);

    text = " hello\tzig\r\nagain";
    text_count = countText(text);
    try std.testing.expectEqual(TextCount{ .lines = 1, .words = 3, .bytes = 17 }, text_count);
}
