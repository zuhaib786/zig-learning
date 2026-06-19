const std = @import("std");
const Mutex = std.Io.Mutex;
const Allocator = std.mem.Allocator;
const sum = @import("sum.zig");

const Counter = struct {
    value: u64 = 0,
    mutex: Mutex = .init,
    pub fn bump(self: *Counter, io: std.Io, n: usize) void {
        for (0..n) |_| {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            self.value += 1;
        }
    }
};

const digest_len = std.crypto.hash.sha2.Sha256.digest_length;

// One result slot per file. The digest is a fixed-size array, so there is no
// per-result allocation — nothing to leak, and each job owns its slot outright.
const SumResult = struct {
    digest: [digest_len]u8 = undefined,
    err: ?anyerror = null,
};

const AtomicCounter = struct {
    value: std.atomic.Value(u64) = .init(0),
    pub fn bump(self: *AtomicCounter, n: usize) void {
        for (0..n) |_| {
            _ = self.value.fetchAdd(1, .monotonic);
        }
    }
};

pub fn BlockingQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();
        buf: [capacity]T = undefined,
        head: usize = 0,
        count: usize = 0,
        mutex: Mutex = .init,
        not_empty: std.Io.Condition = .init,
        not_full: std.Io.Condition = .init,
        closed: bool = false,

        pub fn push(self: *Self, io: std.Io, item: T) void {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            while (self.count == capacity and !self.closed) self.not_full.waitUncancelable(io, &self.mutex);
            if (self.closed) return;
            self.buf[(self.head + self.count) % capacity] = item;
            self.count += 1;
            self.not_empty.signal(io);
        }
        pub fn pop(self: *Self, io: std.Io) ?T {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            while (self.count == 0 and !self.closed) self.not_empty.waitUncancelable(io, &self.mutex);
            if (self.count == 0) return null;
            const item = self.buf[self.head];
            self.head = (self.head + 1) % capacity;
            self.count -= 1;
            self.not_full.signal(io);
            return item;
        }

        pub fn close(self: *Self, io: std.Io) void {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            self.closed = true;
            self.not_empty.broadcast(io);
        }
    };
}

// A unit of work for the pool: hash one file and write the outcome into `result`.
// `path` is borrowed (owned by the caller's path list) and outlives the job.
// A per-file failure (can't open, read error) is recorded in the slot and the job
// returns normally — it is NOT propagated to the pool's `first_error`, which is
// reserved for unexpected job failures. A bad file must not abort the batch.
const ChecksumJob = struct {
    dir: std.Io.Dir,
    io: std.Io,
    path: []const u8,
    result: *SumResult,

    pub fn run(self: ChecksumJob) anyerror!void {
        const file = self.dir.openFile(self.io, self.path, .{}) catch |e| {
            self.result.err = e;
            return;
        };
        defer file.close(self.io);
        var buf: [4096]u8 = undefined;
        var file_reader = file.reader(self.io, &buf);
        self.result.digest = sum.hashReaders(&file_reader.interface) catch |e| {
            self.result.err = e;
            return;
        };
    }
};

// Depth-first collection of every regular file's path (relative to the walk root)
// into `out`. Each appended path is heap-owned by the caller. Mirrors walk.zig's
// traversal but collects instead of printing so the pipeline can index the results.
fn collectFiles(allocator: Allocator, io: std.Io, dir: std.Io.Dir, prefix: []const u8, out: *std.ArrayList([]u8)) !void {
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                const p = try std.fs.path.join(allocator, &.{ prefix, entry.name });
                errdefer allocator.free(p);
                try out.append(allocator, p);
            },
            .directory => {
                const child_path = try std.fs.path.join(allocator, &.{ prefix, entry.name });
                defer allocator.free(child_path);
                var child = dir.openDir(io, entry.name, .{ .iterate = true }) catch |e| switch (e) {
                    error.AccessDenied => continue,
                    else => return e,
                };
                defer child.close(io);
                try collectFiles(allocator, io, child, child_path, out);
            },
            else => {},
        }
    }
}

// Parallel file-checksum pipeline (Sprint 6 capstone deliverable). Walks `root`,
// hashes every file across a worker pool, then prints `<hex>  <path>` in stable
// collection order — NOT completion order. Per-file errors go to `err`; the batch
// never aborts. This is "parallel map" expressed through the worker pool.
pub fn parallelSum(allocator: Allocator, io: std.Io, dir: std.Io.Dir, root: []const u8, out: *std.Io.Writer, err: *std.Io.Writer) !void {
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |p| allocator.free(p);
        paths.deinit(allocator);
    }
    try collectFiles(allocator, io, dir, root, &paths);
    if (paths.items.len == 0) return;

    // One slot per file, indexed by collection order. Jobs write to disjoint slots,
    // so results need NO mutex: the only synchronization is the join in shutdown,
    // which happens-before we read the slots back below.
    const results = try allocator.alloc(SumResult, paths.items.len);
    defer allocator.free(results);
    for (results) |*r| r.* = .{};

    const cpus = std.Thread.getCpuCount() catch 4;
    const workers = @max(1, @min(cpus, paths.items.len));

    // Collected paths are root-prefixed, i.e. relative to the cwd the caller opened
    // `root` from — so jobs open against cwd, not the (already-root) iterate dir.
    const open_base = std.Io.Dir.cwd();
    var pool: Pool(ChecksumJob) = .{};
    try pool.start(workers, io, allocator);
    for (paths.items, results) |p, *r| {
        pool.submit(.{ .dir = open_base, .io = io, .path = p, .result = r }, io);
    }
    try pool.shutdown(io, allocator); // joins every worker before we touch `results`

    for (paths.items, results) |p, r| {
        if (r.err) |e| {
            try err.print("{s}: {s}\n", .{ p, @errorName(e) });
        } else {
            try out.print("{s}  {s}\n", .{ std.fmt.bytesToHex(r.digest, .lower), p });
        }
    }
}

pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();
        queue: BlockingQueue(T, 100) = .{},
        mutex: Mutex = .init,
        numWorkers: usize = 0,
        threads: []std.Thread = &.{},
        first_error: ?anyerror = null,

        fn workerLoop(self: *Self, io: std.Io) void {
            while (self.queue.pop(io)) |job| {
                job.run() catch |e| {
                    self.record_first_error(e, io);
                };
            }
        }

        fn record_first_error(self: *Self, e: anyerror, io: std.Io) void {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            if (self.first_error == null)
                self.first_error = e;
        }

        pub fn start(self: *Self, numWorkers: usize, io: std.Io, allocator: Allocator) !void {
            self.threads = try allocator.alloc(std.Thread, numWorkers);
            errdefer {
                allocator.free(self.threads);
                self.threads = &[_]std.Thread{};
            }
            var filled: usize = 0;
            errdefer {
                // Workers already spawned are blocked in queue.pop; we must close
                // the queue before joining or this error path deadlocks.
                self.queue.close(io);
                for (self.threads[0..filled]) |thread| {
                    thread.join();
                }
            }
            while (filled < numWorkers) : (filled += 1) {
                self.threads[filled] = try std.Thread.spawn(
                    .{},
                    workerLoop,
                    .{ self, io },
                );
            }
        }
        pub fn submit(self: *Self, job: T, io: std.Io) void {
            self.queue.push(io, job);
        }
        pub fn shutdown(self: *Self, io: std.Io, allocator: Allocator) !void {
            self.queue.close(io);
            for (self.threads) |thread| {
                thread.join();
            }
            allocator.free(self.threads);
            const ans = self.first_error;
            self.* = .{};
            return ans orelse {};
        }
    };
}

test "test counter" {
    const io = std.testing.io;
    var counter: Counter = .{};
    var threads: [8]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (0..spawned) |i| {
        threads[i].join();
    };
    for (0..8) |i| {
        threads[i] = try std.Thread.spawn(.{}, Counter.bump, .{ &counter, io, 100_000 });
        spawned += 1;
    }
    for (threads) |thread| {
        thread.join();
    }
    try std.testing.expectEqual(800_000, counter.value);
}
test "Atomic counter" {
    var counter: AtomicCounter = .{};
    var threads: [8]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (0..spawned) |i| {
        threads[i].join();
    };
    for (0..8) |i| {
        threads[i] = try std.Thread.spawn(.{}, AtomicCounter.bump, .{ &counter, 100_000 });
        spawned += 1;
    }
    for (threads) |thread| {
        thread.join();
    }
    try std.testing.expectEqual(800_000, counter.value.load(.monotonic));
}

// --- helpers for the blocking-queue tests (spawn needs named functions) ---
const TQ = BlockingQueue(u64, 4); // small capacity on purpose: forces both wait paths

fn produceOnes(q: *TQ, io: std.Io, m: usize) void {
    for (0..m) |_| q.push(io, 1);
}

fn consumeSum(q: *TQ, io: std.Io, k: usize, total: *std.atomic.Value(u64)) void {
    for (0..k) |_| _ = total.fetchAdd(q.pop(io).?, .monotonic); // never closed here ⇒ pop is non-null
}

fn consumeExpectOrder(q: *TQ, io: std.Io, n: usize, ok: *std.atomic.Value(bool)) void {
    for (0..n) |expected| {
        if (q.pop(io).? != @as(u64, expected)) ok.store(false, .monotonic);
    }
}

test "blocking queue: producers and consumers all balance out" {
    const io = std.testing.io;
    var queue: TQ = .{ .mutex = .init };
    var total: std.atomic.Value(u64) = .init(0);

    const producers = 4;
    const consumers = 4;
    const per_producer = 10_000;
    // chosen so the work divides evenly → each consumer pops a known count and the test
    // terminates without needing shutdown logic. total pushed == total popped, so no deadlock.
    const per_consumer = (producers * per_producer) / consumers;

    var pthreads: [producers]std.Thread = undefined;
    var cthreads: [consumers]std.Thread = undefined;

    // start consumers first: they block on `not_empty` until producers feed the queue.
    for (&cthreads) |*t| t.* = try std.Thread.spawn(.{}, consumeSum, .{ &queue, io, per_consumer, &total });
    for (&pthreads) |*t| t.* = try std.Thread.spawn(.{}, produceOnes, .{ &queue, io, per_producer });

    for (pthreads) |t| t.join();
    for (cthreads) |t| t.join();

    // every "1" pushed was popped exactly once → the sum is the total item count.
    try std.testing.expectEqual(@as(u64, producers * per_producer), total.load(.monotonic));
}

test "blocking queue: single producer/consumer preserves FIFO order" {
    const io = std.testing.io;
    var queue: TQ = .{ .mutex = .init };
    var ok: std.atomic.Value(bool) = .init(true);
    const n = 5_000; // > capacity, so the producer repeatedly blocks on `not_full`

    const consumer = try std.Thread.spawn(.{}, consumeExpectOrder, .{ &queue, io, n, &ok });
    for (0..n) |i| queue.push(io, @as(u64, i)); // push 0,1,2,...,n-1 in order
    consumer.join();

    // one producer + one consumer ⇒ items must come out in the exact order they went in.
    try std.testing.expect(ok.load(.monotonic));
}

// --- worker-pool tests ---
// A job that carries its own data and exposes `run`. `fail` lets us inject an error.
const TestJob = struct {
    counter: *std.atomic.Value(u64),
    fail: bool = false,
    pub fn run(self: TestJob) anyerror!void {
        _ = self.counter.fetchAdd(1, .monotonic);
        if (self.fail) return error.Boom;
    }
};

test "pool: runs every submitted job exactly once" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var counter: std.atomic.Value(u64) = .init(0);

    var pool: Pool(TestJob) = .{};
    try pool.start(4, io, allocator);

    const jobs = 5_000;
    for (0..jobs) |_| pool.submit(.{ .counter = &counter }, io);
    try pool.shutdown(io, allocator); // returning (not hanging) is itself proof the workers exited

    try std.testing.expectEqual(@as(u64, jobs), counter.load(.monotonic));
}

test "pool: a failing job propagates its error to the caller" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var counter: std.atomic.Value(u64) = .init(0);

    var pool: Pool(TestJob) = .{};
    try pool.start(4, io, allocator);

    const jobs = 200;
    for (0..jobs) |i| pool.submit(.{ .counter = &counter, .fail = (i == 100) }, io);
    const result = pool.shutdown(io, allocator);

    try std.testing.expectError(error.Boom, result);
    // graceful, not abort-on-first-error: every job still ran despite the failure.
    try std.testing.expectEqual(@as(u64, jobs), counter.load(.monotonic));
}

test "pool: shuts down cleanly with no jobs (idle workers must wake and exit)" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    // If close() used signal() instead of broadcast(), only one of the 4 idle workers
    // would wake and this would hang. Reaching the end proves all four exited.
    var pool: Pool(TestJob) = .{};
    try pool.start(4, io, allocator);
    try pool.shutdown(io, allocator);
}

// --- parallel checksum pipeline test ---
test "parallel sum: every file's digest matches serial hashReaders" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // Build a small tree on disk (with a subdir, to exercise recursion).
    const root = "zig-cache-psum-test";
    var cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root);
    defer cwd.deleteTree(io, root) catch {};
    try cwd.createDirPath(io, root ++ "/sub");

    const files = [_]struct { path: []const u8, data: []const u8 }{
        .{ .path = root ++ "/a.txt", .data = "abc" },
        .{ .path = root ++ "/b.txt", .data = "hello world" },
        .{ .path = root ++ "/sub/c.txt", .data = "" }, // empty file
        .{ .path = root ++ "/sub/d.txt", .data = "the quick brown fox jumps over the lazy dog" },
    };
    for (files) |f| try cwd.writeFile(io, .{ .sub_path = f.path, .data = f.data });

    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var out_w = std.Io.Writer.fixed(&out_buf);
    var err_w = std.Io.Writer.fixed(&err_buf);

    var dir = try cwd.openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    try parallelSum(allocator, io, dir, root, &out_w, &err_w);

    const out = out_w.buffered();
    try std.testing.expectEqualStrings("", err_w.buffered()); // no per-file errors

    // Output order is collection order (not completion order), so for each file we
    // assert its expected `<hex>  <path>` line appears — independent of which line.
    for (files) |f| {
        var reader = std.Io.Reader.fixed(f.data);
        const digest = try sum.hashReaders(&reader); // the serial reference
        const hex = std.fmt.bytesToHex(digest, .lower);
        var line_buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf, "{s}  {s}\n", .{ hex, f.path });
        try std.testing.expect(std.mem.indexOf(u8, out, line) != null);
    }
}
