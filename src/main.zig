const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const testing = std.testing;
const z9p = @import("z9p.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const stream = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 5640);
    defer stream.close();

    std.debug.print("Connected\n", .{});

    var client = z9p.simpleClient(allocator, stream.reader(), stream.writer());
    defer client.deinit();

    try client.connect(std.math.maxInt(u32));

    const root = try client.attach(null, "dante", "");
    defer root.clunk() catch unreachable;
    std.debug.print("root: {any}\n", .{ root });

    const top_dir = try root.walk(&.{ "" });
    defer top_dir.clunk() catch unreachable;
    std.debug.print("top_dir: {any}\n", .{ top_dir });

    try top_dir.open(.{});
    std.debug.print("opened: {any}\n", .{ top_dir });

    const stat = try top_dir.stat();
    defer stat.deinit();
    std.debug.print("stat: {any}\n", .{ stat });
    std.debug.print("size: {d}\n", .{ stat.length });

    const buf = try top_dir.reader().readAllAlloc(allocator, 99999);
    defer allocator.free(buf);
    std.debug.print("reader: {any}\n", .{ buf });

    const files = try top_dir.files();
    defer files.deinit();
    for (files.stats) |s| {
        std.debug.print("{s} {s:6} {s:6} {d:8} {s}\n", .{ s.mode, s.uid, s.gid, s.length, s.name });
    }

    const tmp = try root.walk(&.{ "tmp" });
    try tmp.create("testing", .{ .user_read = true, .user_write = true, .group_read = true, .world_read = true }, .{});
    try tmp.remove();

    const passwd = try root.walk(&.{ "etc", "passwd" });
    defer passwd.clunk() catch unreachable;
    try passwd.open(.{});
    const pass_data = try passwd.reader().readAllAlloc(allocator, 99999);
    defer allocator.free(pass_data);
    std.debug.print("/etc/passwd:\n{s}\n", .{ pass_data });

    const new_file = try root.walk(&.{ "tmp" });
    defer new_file.remove() catch unreachable;
    try new_file.create("new_thing.txt", .{ .user_write = true, .user_read = true }, .{ .perm = .write });
    const tons_of_data = [_]u8{'a'} ** 10000;
    try new_file.writer().print(&tons_of_data, .{});
}
