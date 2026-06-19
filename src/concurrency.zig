const std = @import("std");
const Mutex = std.Io.Mutex;
const Allocator = std.mem.Allocator;

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

fn consumeSum(q: *TQ, io: std.Io, k: usize, sum: *std.atomic.Value(u64)) void {
    for (0..k) |_| _ = sum.fetchAdd(q.pop(io).?, .monotonic); // never closed here ⇒ pop is non-null
}

fn consumeExpectOrder(q: *TQ, io: std.Io, n: usize, ok: *std.atomic.Value(bool)) void {
    for (0..n) |expected| {
        if (q.pop(io).? != @as(u64, expected)) ok.store(false, .monotonic);
    }
}

test "blocking queue: producers and consumers all balance out" {
    const io = std.testing.io;
    var queue: TQ = .{ .mutex = .init };
    var sum: std.atomic.Value(u64) = .init(0);

    const producers = 4;
    const consumers = 4;
    const per_producer = 10_000;
    // chosen so the work divides evenly → each consumer pops a known count and the test
    // terminates without needing shutdown logic. total pushed == total popped, so no deadlock.
    const per_consumer = (producers * per_producer) / consumers;

    var pthreads: [producers]std.Thread = undefined;
    var cthreads: [consumers]std.Thread = undefined;

    // start consumers first: they block on `not_empty` until producers feed the queue.
    for (&cthreads) |*t| t.* = try std.Thread.spawn(.{}, consumeSum, .{ &queue, io, per_consumer, &sum });
    for (&pthreads) |*t| t.* = try std.Thread.spawn(.{}, produceOnes, .{ &queue, io, per_producer });

    for (pthreads) |t| t.join();
    for (cthreads) |t| t.join();

    // every "1" pushed was popped exactly once → the sum is the total item count.
    try std.testing.expectEqual(@as(u64, producers * per_producer), sum.load(.monotonic));
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
