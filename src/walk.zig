const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn walk(allocator: Allocator, io: std.Io, dir: std.Io.Dir, prefix: []const u8, out: *std.Io.Writer, err: *std.Io.Writer) !void {
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                const child_path = try std.fs.path.join(allocator, &.{ prefix, entry.name });
                defer allocator.free(child_path);
                try out.print("{s}/\n", .{child_path});
                var child = dir.openDir(io, entry.name, .{ .iterate = true }) catch |e| switch (e) {
                    error.AccessDenied => {
                        try err.print("{s}: Permission Denied\n", .{child_path});
                        continue;
                    },
                    else => return e,
                };
                defer child.close(io);
                try walk(allocator, io, child, child_path, out, err);
            },
            .sym_link => {
                try out.print("Sym link: {s}/{s}\n", .{ prefix, entry.name }); // ideally i want to print with blue to indicate sym-link
            },
            .file => {
                try out.print("{s}/{s}\n", .{ prefix, entry.name });
            },
            else => {},
        }
    }
}

pub fn walkCollect(allocator: Allocator, io: std.Io, dir: std.Io.Dir, prefix: []const u8, list: *std.ArrayList([]const u8), out: *std.Io.Writer, err: *std.Io.Writer) !void {
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                const child_path = try std.fs.path.join(allocator, &.{ prefix, entry.name });
                defer allocator.free(child_path);
                try out.print("{s}/\n", .{child_path});
                var child = dir.openDir(io, entry.name, .{ .iterate = true }) catch |e| switch (e) {
                    error.AccessDenied => {
                        try err.print("{s}: Permission Denied\n", .{child_path});
                        continue;
                    },
                    else => return e,
                };
                defer child.close(io);
                try walk(allocator, io, child, child_path, out, err);
            },
            .sym_link => {
                try out.print("Sym link: {s}/{s}\n", .{ prefix, entry.name }); // ideally i want to print with blue to indicate sym-link
            },
            .file => {
                try out.print("{s}/{s}\n", .{ prefix, entry.name });
                var result = try allocator.alloc(u8, prefix.len + entry.name.len + 1);
                errdefer allocator.free(result);
                @memcpy(result[0..prefix.len], prefix);
                @memcpy(result[prefix.len .. prefix.len + 1], "/");
                @memcpy(result[prefix.len + 1 ..], entry.name);
                try list.append(allocator, result);
            },
            else => {},
        }
    }
}
