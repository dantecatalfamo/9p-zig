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

    var iter = z9p.messageReceiver(allocator, stream.reader());
    var sender = z9p.messageSender(stream.writer());

    var client = z9p.simpleClient(allocator, stream.reader(), stream.writer());
    defer client.deinit();

    try client.connect(std.math.maxInt(u32));

    // try sender.tversion(std.math.maxInt(u32), z9p.proto);
    // const rversion = try iter.next();
    // defer rversion.deinit();
    // std.debug.print("rversion: {any}\n", .{ rversion });

    const root = try client.attach(null, "dante", "");
    std.debug.print("root: {any}\n", .{ root });

    // try sender.tattach(0, 0, null, "dante", "");
    // const rattach = try iter.next();
    // defer rattach.deinit();
    // std.debug.print("rattach: {any}\n", .{ rattach });

    var top_dir = try root.walk(&.{});
    std.debug.print("top_dir: {any}\n", .{ top_dir });

    // try sender.twalk(0, 0, 1, &.{});
    // const rwalk = try iter.next();
    // defer rwalk.deinit();
    // std.debug.print("rwalk: {any}\n", .{ rwalk });

    try top_dir.open(.{});
    std.debug.print("opened: {any}\n", .{ top_dir });

    // try sender.topen(0, 1, .{});
    // const ropen = try iter.next();
    // defer ropen.deinit();
    // std.debug.print("ropen: {any}\n", .{ ropen });

    const stat = try top_dir.stat();
    defer stat.deinit();
    std.debug.print("stat: {any}\n", .{ stat });

    // try sender.tstat(0, 1);
    // const rstat = try iter.next();
    // defer rstat.deinit();
    // std.debug.print("rstat: {any}\n", .{ rstat });

    try sender.tread(0, 1, 0, 1024);
    const rread = try iter.next();
    defer rread.deinit();
    std.debug.print("rread: {s}\n", .{ rread });

    var buf = std.io.fixedBufferStream(rread.command.rread.data);
    const dir_stat = try z9p.Stat.parse(allocator, buf.reader());
    defer dir_stat.deinit();
    std.debug.print("stat: {any}\n", .{ dir_stat });
}
