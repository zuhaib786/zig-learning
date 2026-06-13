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

## Capstone: `zcage` — Tiny Container Runtime for Coding Agents (Weeks 4–6)

Linux-first tiny runtime to serve as the isolation layer for a future coding copilot: sandboxes, workspace mounts, resource limits, logs, clean teardown. Not a Docker clone.

**Platform note:** namespaces, cgroups, `pivot_root` are Linux-only. Edit anywhere, test on Linux (VM is fine).

Eleven capstone phases compressed into five milestones. Each milestone ends with something you can demo from the shell.

### M1 — Skeleton + Process Runner (Days 1–4)

- Module layout: `main`, `cli`, `runtime`, `process`, `state`, `logs` (add `rootfs`, `mounts`, `cgroups`, `agent` only when their milestone starts).
- Real arg parsing with subcommands, `--help` everywhere, exit codes. CLI parsing has tests.
- `zcage run -- <cmd>`: env vars, workdir, stdout/stderr capture, exit status, timeout kill. Metadata stored in a state dir.
- Linux-only commands fail clearly elsewhere.

**Demo:** `zcage run --timeout 5s -- sleep 60` times out and reports it.

### M2 — Filesystem + Namespace Isolation (Days 5–9)

- Rootfs validation, bind mounts (`host:guest`), read-only mounts, mount `/proc`.
- `chroot` (skip `pivot_root` — it was a stretch goal; it's now cut).
- Namespaces: `--pid`, `--uts`, `--ipc`, `--mount`, `--network none`. Cut user-namespace UID mapping unless it blocks you.
- Reliable unmount/cleanup on exit.

**Demo:** `zcage run --rootfs ./rootfs --mount "$PWD:/workspace" -- /bin/sh` — own PID 1, own hostname, host invisible except the mount.

### M3 — Cgroups + State + Logs (Days 10–14)

- Cgroup v2 per container: `--memory`, `--cpus`, `--pids`. Cleanup after exit.
- Unique container IDs, records in the state dir.
- `zcage ps`, `zcage logs <id>`, `zcage kill <id>`.
- Threaded log capture to files + ring buffer for recent lines (your Sprint 3/6 code pays off here). No deadlocks on huge output.

**Demo:** a memory-hog dies under `--memory 100m`; `zcage logs` works after exit.

### M4 — Images + Security Defaults (Days 15–17)

- `zcage image import <tar> <name>`, `list`, `remove`, manifest with content hash.
- Hardening: drop capabilities, read-only rootfs mode, no-new-privileges. Cut seccomp (was a stretch goal).
- Document honestly what this does and does not protect against.

**Demo:** import an Alpine tar, run a sandboxed shell from it read-only.

### M5 — Agent Mode + Orchestration (Days 18–24)

- `zcage agent init/run/exec/logs/clean` — sessions with task file, command history, logs, limits, workspace mount config.
- Agent default profile: no network, memory/CPU limits, read-only base, workspace mount only.
- Job queue with states (pending/running/succeeded/failed/canceled), worker threads for concurrent jobs, cancellation/timeout, dependency-ordered steps, JSON output so another program can drive it.
- No AI model — this is the execution substrate.

**Demo:** two concurrent agent sessions running `zig build test` in separate sandboxes, driven via JSON output, no corrupted state.

### Polish day (Day 25)

One day, not a phase: README with architecture + security model + limitations, sample rootfs instructions, and one rough startup-overhead measurement. Cut the full benchmark suite.

## Timeline

- Week 1: Sprints 1–3
- Week 2: Sprints 4–5
- Week 3: Sprint 6 + Capstone M1
- Weeks 4–6: Capstone M2–M5 + polish

One flex rule: Sprint 2 (allocators/ownership) and Sprint 6 (threads) may run over their timebox. Nothing else may.

## Cut List (deliberately not built)

Deque, set ops, symbol table, linear search, heap sort, standalone top-k, pre/post-order traversal drills, AVL/red-black, adjacency matrix, connected components, MST, env inspector, temp-file exercise, standalone parallel map, `pivot_root`, user-ns UID mapping, seccomp, full benchmark suite. If any of these turns out to be needed, the capstone will tell you — build it then.

## Final Confidence Checklist

- Build and test Zig projects without templates.
- Use allocators intentionally; ship leak-free code.
- Write CLI tools with clear errors and exit codes.
- Implement and test core data structures and algorithms; explain their complexity.
- Work with files, binary formats, paths, and processes.
- Design a multithreaded worker pipeline that shuts down cleanly.
- Ship a non-trivial runtime with isolation, resource limits, supervision, and concurrency.
