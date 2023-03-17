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

    try sender.tversion(std.math.maxInt(u32), z9p.proto);
    const rversion = try iter.next();
    defer rversion.deinit();
    std.debug.print("rversion: {any}\n", .{ rversion });

    try sender.tattach(0, 0, null, "dante", "");
    const rattach = try iter.next();
    defer rattach.deinit();
    std.debug.print("rattach: {any}\n", .{ rattach });

    try sender.twalk(0, 0, 1, &.{});
    const rwalk = try iter.next();
    defer rwalk.deinit();
    std.debug.print("rwalk: {any}\n", .{ rwalk });

    try sender.topen(0, 1, .{});
    const ropen = try iter.next();
    defer ropen.deinit();
    std.debug.print("ropen: {any}\n", .{ ropen });

    try sender.tstat(0, 1);
    const rstat = try iter.next();
    defer rstat.deinit();
    std.debug.print("rstat: {any}\n", .{ rstat });

    try sender.tread(0, 1, 0, 1024);
    const rread = try iter.next();
    defer rread.deinit();
    std.debug.print("rread: {s}\n", .{ rread });

    var buf = std.io.fixedBufferStream(rread.command.rread.data);
    const stat = try z9p.Stat.parse(allocator, buf.reader());
    defer stat.deinit(allocator);
    std.debug.print("stat: {any}\n", .{ stat });
}
