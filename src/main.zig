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

    try sender.tattach(0, 0, null, "dante", "/home/dante/dired.sh");
    const rattach = try iter.next();
    defer rattach.deinit();
    std.debug.print("rattach: {any}\n", .{ rattach });

    try sender.tstat(1, 0);
    const rstat = try iter.next();
    defer rstat.deinit();
    std.debug.print("rstat: {any}\n", .{ rstat });

    try sender.tread(1, 0, 0, 1024);
    const rread = try iter.next();
    defer rattach.deinit();
    std.debug.print("rread: {s}\n", .{ rread });
}
