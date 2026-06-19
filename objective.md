# Zig Learning Objective (Velocity Edition)

Goal: become comfortable writing practical Zig — I/O, memory, strings, data structures, algorithms, CLI tools, systems programming, and threads — as fast as possible without skipping the fundamentals that actually matter (allocators, ownership, error handling, concurrency).


## Velocity Rules

- Every sprint is timeboxed. When the timebox ends, ship what you have and move on. Gaps get fixed when they bite you later — that's when learning sticks.
- Learn by building the deliverable, not by studying first. Read docs only when blocked.
- One CLI binary grows across all sprints. Each sprint adds subcommands to it instead of starting new projects.
- Tests are mandatory for data structures and algorithms; optional everywhere else.
- `zig build test` must pass at the end of every working day. Commit daily.
- Stretch goals are deleted, not deferred. If something below isn't listed, don't build it.
- If a concept is confusing, write 3 lines in `notes/`, not 3 pages.
- Standard library first. No third-party dependencies.

## Sprint 1 — Syntax + CLI in One Shot (Days 1–3)

Skip the toy-function phase. Learn syntax by building a real CLI on day one.

**Build:** a single executable with subcommands:
- `echo` — prints arguments
- `cat <file>` — prints file contents
- `count [file]` — bytes, lines, words from file or stdin
- `copy <src> <dst>`

While building it you will necessarily hit: `build.zig`, slices vs arrays, structs, enums, optionals (`?T`), error unions (`!T`), `defer`/`errdefer`, `switch`, `for`/`while`, buffered writers and flushing, stdout vs stderr.

**Tests:** core logic (counting, arg validation) lives outside `main` and has tests.

**Move on when:** the CLI handles missing files and empty input with clean errors on stderr, and you can explain arrays vs slices and when to flush.

## Sprint 2 — Memory, Allocators, Strings (Days 4–6)

This is the one sprint you do NOT rush. Allocators are the whole point of Zig.

**Build:** `src/strings.zig` with dup, join, split, trim, reverse, and a dynamic string builder — all taking an explicit allocator. Add a `freq` subcommand: top-k most frequent words from stdin (this forces `std.StringHashMap` + key lifetime handling early).

**Tests:** every function tested with `std.testing.allocator` so leaks fail the build. At least one test that would leak if you freed wrong — then fix it.

**Move on when:** zero leaks, and for every returned slice you can say who owns it and who frees it. You've used both GPA and an arena and know when each fits.

## Sprint 3 — Data Structures Blitz (Days 7–10)

**Build:** stack, queue, ring buffer, generic dynamic array (then compare with `std.ArrayList`), and an LRU cache (hash map + linked list). Cut: deque, set operations, symbol table — `std` covers them and they teach nothing new after the above.

**Tests:** empty, growth, boundary, and cleanup cases for each. Leak-free.

**Move on when:** length vs capacity and amortized append are obvious to you, and the LRU cache works.

## Sprint 4 — Algorithms Blitz (Days 11–14)

**Build:**
- Binary search (with insertion-position behavior)
- Insertion sort, merge sort, quick sort — generic via `comptime` type params and comparator functions. Cut: linear search (trivial), heap sort and top-k (the heap shows up in Dijkstra anyway).
- BST: insert, find, delete, min/max, in-order traversal. Cut: pre/post-order ceremony, AVL/red-black.
- Graphs: adjacency list only (cut matrix), BFS, DFS, topological sort, Dijkstra. Cut: connected components (it's BFS in a loop), MST.
- A `graph` subcommand that loads edges from a text file and runs an algorithm.

**Tests:** sorts against `std.sort` on empty/single/sorted/reversed/duplicate/random inputs; BST delete cases (leaf, one child, two children); graphs with cycles and disconnected nodes.

**Move on when:** you can state complexity for everything you wrote and all tests pass. Don't memorize — derive.

## Sprint 5 — Systems Programming (Days 15–17)

**Build:**
- Recursive directory walker (`walk` subcommand)
- Checksum utility (`sum` subcommand)
- Binary read/write for a tiny custom format with magic header + version
- Cut: env inspector and temp-file workflow as standalone items — you'll touch both inside the capstone anyway.

**Move on when:** symlinks, missing paths, and permission errors are handled, and binary I/O vs text I/O is clear.

## Sprint 6 — Concurrency (Days 18–21)

**Build:**
- Thread-safe counter (mutex version and atomic version — feel the difference)
- Producer-consumer queue with condition variables
- Worker pool with graceful shutdown and error propagation to the caller
- Parallel file-checksum pipeline reusing Sprint 5's `sum`
- Cut: parallel map as a separate exercise — the worker pool IS parallel map.

**Move on when:** workers shut down without hanging, worker errors reach the caller, and you can justify mutex vs atomic for each use.

That's it for fundamentals. CLI polish (the old Phase 11) is folded into Capstone M1 where it's actually needed.

## Capstone: `lzdb` — A Crash-Safe Embedded Storage Engine (Weeks 4–7)

A log-structured (LSM) key-value storage engine. Embedded, single-process, standard library only — runs natively on macOS and Linux. **Architectural reference: RocksDB / LevelDB (the LSM design). Testing-philosophy inspiration: TigerBeetle (deterministic simulation testing) — *not* its storage internals.** Not a SQLite clone; a focused study in durability and failure. Read alongside DDIA Ch. 3 and the RocksDB MANIFEST/Compaction wikis (links at the end).

The point isn't to ship a database the world needs. It's to rehearse how the people behind systems like RocksDB and TigerBeetle actually work: take a known category, pick **one axis** to be radically better on, go absurdly deep, and prove correctness by *simulating failure* instead of hoping it away.

**Platform note:** cross-platform. `sync` (`File.sync`), file I/O, and your own *simulated* disk run anywhere — edit and test on your Mac with a tight loop. No VM, no Linux-only syscalls.

**The fault model — state it before writing any code.** Software *cannot* survive a disk that lies about a successful `sync` (that needs replication or special hardware; both out of scope). The honest contract `lzdb` provides:
- Writes may be partial, reordered, or fail outright.
- `sync` may fail.
- A crash may discard any data not yet `sync`ed.
- **After `sync` returns success, the bytes written before it are durable.** That single promise is the whole game.
The simulator may *fail* a `sync`, but it must **never report success and then discard the data** — otherwise durability is impossible by construction.

**Crash classes — don't conflate them.** `kill -9` tests *process-crash recovery*: unsynced data is *allowed* to vanish, and recovery must stay consistent. Only the **simulator (M4)** tests *power-loss* faults — torn writes and lost/reordered unsynced writes.

**The `Storage` interface — from the first commit, not M4.** All engine I/O goes through one indirection so the simulator drops in later without a rewrite:
```
const Storage = struct {
    open:          *const fn (...) ...,
    create:        *const fn (...) ...,
    close:         *const fn (...) ...,
    read:          *const fn (...) ...,
    write:         *const fn (...) ...,
    fileSize:      *const fn (...) ...,
    truncate:      *const fn (...) ...,
    sync:          *const fn (...) ...,
    rename:        *const fn (...) ...,
    remove:        *const fn (...) ...,
    listDirectory: *const fn (...) ...,
    syncDirectory: *const fn (...) ...,
};
```
M1 ships `RealStorage` (over `std.Io`); M4 adds `SimulatedStorage`. The engine never touches the filesystem directly.

**North star (a mini "Tiger Style"):**
- Durability is the contract above — kept exactly, claimed honestly (no "survives a lying disk").
- The on-disk log **+ manifest** are the source of truth; every in-memory structure is a cache rebuilt from them.
- Every operation / WAL record / SSTable entry carries a **monotonic sequence number**. The manifest persists `last_sequence`, and sequence numbers are never reused after recovery. "Newest file wins" is *not* a correct ordering model after recovery and compaction.
- Prepare every fallible allocation *before* you `sync` a record — a record must never become durable while `put()` returns `error.OutOfMemory`.
- Engine API is `open / put / get / delete / close`; the REPL is just a client of it.
- **Concurrency model:** the capstone is deliberately single-threaded. The public API is not thread-safe, flush and compaction run inline, and callers must serialize access. This keeps the durability proof about storage ordering rather than hidden data races. Background compaction is explicitly out of scope; adding it later would require pinned immutable versions (or holding a read lock through lookup) so obsolete files cannot be deleted while a reader still uses them—a lock around only the live-set swap is insufficient.
- Test by *simulating* faults, not hoping. Standard library only; draws directly on the earlier binary-format, data-structure, algorithm, and checksum work.

Five milestones (28 days + a polish day ≈ four weeks). Each ends with a demo — usually crash, recover, verify.

### M1 — Storage Interface + Log + WAL + Recovery (Days 1–5)

The durability core, behind the `Storage` interface from commit one.

- The `Storage` interface + `RealStorage` over `std.Io`. The engine only ever calls `Storage`.
- Every on-disk file starts with a **magic value + format version**; unknown versions are rejected rather than guessed.
- **WAL framing decision:** use LevelDB-style fixed **32 KiB physical blocks**, so damaged framing cannot poison the rest of the file. A logical operation is encoded as `sequence | kind | key_len | value_len | key | value` and split when necessary into `full / first / middle / last` fragments. No physical fragment crosses a block boundary.
- Each fragment is `checksum | length | fragment_kind | payload`. The checksum covers **length + fragment kind + payload** (everything except the checksum field itself), so corruption of the framing header is detected. Unused bytes at the end of a block are zero-filled; recovery can always resynchronize at the next fixed block boundary.
- Define hard maximum key, value, and record sizes. Recovery validates lengths and integer arithmetic **before allocating or slicing**, so a corrupt file cannot request unbounded memory or overflow an offset.
- Append-only WAL writer; `Storage.sync` is the durability boundary — `put` reports success only *after* the record is `sync`ed (and after all its allocations have already succeeded).
- **Recovery with tail repair** — not merely "stop at corruption":
  - Validate every fragment and reassemble complete logical operations, tracking `last_valid_offset` at the end of the last fully-valid logical operation.
  - A short/torn fragment or incomplete fragment chain in the **final physical block** is expected after a crash → truncate the WAL back to `last_valid_offset`, so future appends cannot land after damaged bytes.
  - Because block boundaries provide resynchronization, recovery can inspect subsequent blocks. A corrupt block followed by any non-empty block is **mid-log corruption** and fatal; refuse to open rather than silently discard later records.
- Engine API: `open / put / get / delete / close`. A separate REPL drives them.

**Demo:** `put` keys, `kill -9` mid-run, reopen → every `sync`-acknowledged write is present; a torn trailing record is truncated away; the WAL is left clean for new appends.

**Move on when:** you can state precisely which writes survive a process crash and why `sync` is the boundary; recovery truncates a torn tail and treats mid-log corruption as fatal.

### M2 — Memtable + Reads + Tombstones (Days 6–9)

- In-memory **memtable** — a hash map is fine (you'll sort its entries at flush time in M3; no need to swap structures). Rebuilt entirely from the WAL on recovery.
- `get / put / delete`: `put` durably appends to the WAL **then** updates the memtable; `delete` writes a durable **tombstone** record (a forgotten delete is a resurrected key). All allocation the memtable update needs happens *before* the `sync`.
- Invariant to defend: the memtable is a *pure function of the log* — discard it, replay, get **semantically identical** state (same key→value/tombstone set; hash-map *layout* is not stable, so not "bit-identical").

**Demo:** interleave puts/overwrites/deletes; crash; recover → reads return the last `sync`-acknowledged value, or "not found" for tombstoned keys.

**Move on when:** for any key you can name the authority (log) vs the cache (memtable); a `delete` survives a crash; a mid-`put` allocation failure never leaves a durable-but-unreported record.

### M3 — SSTables + Manifest + Compaction (the LSM core) (Days 10–16)

Architectural reference here is **LevelDB/RocksDB**, not TigerBeetle.

- **SSTable:** flush a frozen memtable to an immutable, **sorted** segment (sorted blocks + index/footer). M3 protects the file structure and footer with checksums sufficient to reject an incomplete segment; optional checksums on every data block belong to the M5 crash-hardening axis. Sort the hash-map's entries during the flush.
- Reads: memtable → SSTables ordered by **sequence number** (not file mtime). Within an SSTable, binary-search with your Sprint 4 `lowerBound`.
- **Read invariant:** each flush produces an SSTable whose sequence range is strictly newer than every existing SSTable range. Full compaction replaces all selected ranges with their combined range, and subsequent flushes are strictly newer. Therefore live SSTable sequence ranges remain disjoint and totally ordered; the first matching entry found newest → oldest is authoritative.
- **MANIFEST — a `rename` is not a transaction.** The live file set can't be changed atomically with `rename` alone (it spans several SSTables + WAL deletion). Keep an append-only, `sync`ed **manifest** of file-set edits; on open, the manifest *defines* the authoritative live set. (This is exactly why RocksDB has a MANIFEST.)
- **Manifest recovery:** manifest edits use the same fixed-block fragment framing and corruption policy as the WAL and repair a torn tail. The recovered manifest provides `last_sequence`, `next_file_number`, active WAL generations, and the live SSTable set. Sequence and file numbers are never reused. Filesystem contents are not authority: temporary/orphan files not named by the manifest are ignored and safely removed during recovery.
- **WAL rotation by generations** — never truncate the sole WAL in place during a flush:
  1. Freeze the current memtable; start a **new** WAL + mutable memtable.
  2. Flush the frozen memtable to a new SSTable; `sync` it.
  3. Install it via the manifest (`sync` manifest, then directory).
  4. **Only then** delete the old WAL generation.
- **Compaction policy — pick one and write it down: size-tiered *full* compaction for the capstone.** Merge SSTables with a k-way merge (your merge-sort/heap). A **tombstone may be dropped only when the compaction includes every older SSTable that could hold that key** — full compaction satisfies this; partial compaction does not. State the rule explicitly.
- **Commit protocol for any structural change** (flush or compaction), in order: `sync` new files → `rename` temporaries → `sync` directory → append + `sync` manifest edit → delete obsolete files → `sync` directory.

**Demo:** write past memory; watch SSTables + manifest evolve; trigger a compaction; reads stay correct; crash *mid-compaction* and reopen → the manifest names a consistent file set, nothing lost or resurrected.

**Move on when:** you can trace a `get` through memtable → SSTables by sequence; explain read/write/space amplification; flush, rotation, and compaction each commit through the manifest and survive a crash at any step.

### M4 — Deterministic Simulation Testing (the soul) (Days 17–23)

The technique borrowed from **TigerBeetle** — and the milestone that teaches you to *think* like its authors. (It inspires the *testing*, not the LSM design.)

- **`SimulatedStorage`** — the second implementation of your M1 `Storage` interface. Every nondeterministic choice (fault occurrence, partial-write length, crash point) is drawn from a single **PRNG seed**.
- **Fault injection, obeying the fault model:** tear writes (persist only the first N bytes), drop/reorder *unsynced* writes, **fail** `sync` with an error — but a `sync` that *returns success* keeps its data. Crash the engine at any point between `Storage` calls.
- **Reference model:** track each operation through three distinct states: `submitted`, `durable` (its internal `sync` succeeded), and `acknowledged` (the caller received success). A crash may occur after durability but before acknowledgement, so recovery may contain an in-flight/unacknowledged operation. After crash + recovery assert: every caller-acknowledged operation is reflected; the final in-flight operation may be present or absent; no never-submitted operation appears; and no torn record is loaded.
- Harness: loop over seeds → random workload → random crash → recover → assert invariants. A failing seed replays identically, so you debug deterministically.

**Demo:** `lzdb simulate --seed 12345` runs a full crash/recover lifecycle; a deliberately injected durability bug is caught by *some* seed, printed, and reproduced bit-for-bit on rerun.

**Move on when:** you've found and fixed at least one real durability bug *via the simulator*, it honors the fault model, and you can explain why deterministic replay makes storage bugs tractable.

### M5 — Pick Your Axis & Measure It Honestly (Days 24–28)

Where it becomes *yours*. Choose **one** axis, specialize hard, and measure it **apples-to-apples**: identical durability settings and a written workload definition. "Beat SQLite" is marketing; "equal-durability throughput on workload X" is an acceptance criterion.

- **Throughput:** group commit / batching (one `sync` amortized over many ops); report ops/sec vs `sqlite3` configured for the *same* durability (e.g. both `synchronous=FULL`).
- **Crash-safety hardening:** checksums on every SSTable data block + torn-write detection; survive 100k seeded crashes with zero invariant violations.
- **Range queries:** an ordered merge-iterator over memtable + SSTables behind `scan from..to`.

Pick one; the others are out of scope.

**Demo and acceptance criterion depend on the chosen axis:**
- Throughput: an equal-durability SQLite benchmark with configuration and workload spelled out — where you win, where you lose, and *why*.
- Crash-safety hardening: a reproducible seeded-fault report covering 100k crashes with zero invariant violations.
- Range queries: model-based correctness tests plus a defined scan benchmark against SQLite over identical data and ranges.

### Polish day (final)

One day, not a phase: a README with the architecture, the **durability/consistency model stated honestly** (the fault model above — what it guarantees and what it explicitly does *not*, e.g. it does not survive a lying `sync`), the on-disk format + manifest spec, how to run the simulator, and the one apples-to-apples benchmark from M5. Then read a talk on deterministic simulation testing and write 5 lines in `notes/` on what you understand now that you didn't before M4.

### References
- DDIA, Ch. 3 — storage & retrieval (LSM-trees vs B-trees), the conceptual map.
- RocksDB **MANIFEST**: https://github.com/facebook/rocksdb/wiki/MANIFEST — why multi-file atomicity needs a manifest, not `rename`.
- RocksDB **Compaction**: https://github.com/facebook/rocksdb/wiki/Compaction — compaction styles, tombstone-drop rules, amplification trade-offs.
- LevelDB design docs — the original log + SSTable + manifest architecture you're modeling.
- TigerBeetle — deterministic simulation testing (talks + the "Tiger Style" doc). For M4's *philosophy* only; not an LSM reference.

## Timeline

- Week 1: Sprints 1–3
- Week 2: Sprints 4–5
- Week 3: Sprint 6
- Weeks 4–7: Capstone M1–M5 (Storage/WAL/recovery → memtable → LSM/SSTables+manifest → simulation testing → your axis) + polish

One flex rule: Sprint 2 (allocators/ownership) and Sprint 6 (threads) may run over their timebox. Nothing else may.

## Cut List (deliberately not built)

Deque, set ops, symbol table, linear search, heap sort, standalone top-k, pre/post-order traversal drills, AVL/red-black, adjacency matrix, connected components, MST, env inspector, temp-file exercise, standalone parallel map, networking/client-server (the engine stays embedded), SQL / a query language, MVCC & multi-statement transactions, secondary indexes, B-tree storage (LSM only), block compression, bloom filters, replication/consensus (TigerBeetle's VSR — far too big), full benchmark suite. If any of these turns out to be needed, the capstone will tell you — build it then.

## Final Confidence Checklist

- Build and test Zig projects without templates.
- Use allocators intentionally; ship leak-free code.
- Write CLI tools with clear errors and exit codes.
- Implement and test core data structures and algorithms; explain their complexity.
- Work with files, binary formats, paths, and processes.
- Design a multithreaded worker pipeline that shuts down cleanly.
- Ship a non-trivial crash-safe storage engine: an on-disk LSM format with a write-ahead log, recovery, and compaction.
- Reason about durability and failure: know exactly which writes survive a crash and why, and validate it with deterministic simulation testing (fault injection + seeded replay).
