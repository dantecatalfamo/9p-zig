const std = @import("std");
const io = std.io;
const mem = std.mem;
const math = std.math;
const testing = std.testing;
const FileReader = std.fs.File.Reader;
const FileWriter = std.fs.File.Writer;

const proto = "9P2000";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();

    const stream = try std.net.tcpConnectToHost(allocator, "127.0.0.1", 5640);
    defer stream.close();

    std.debug.print("Connected\n", .{});

    var iter = messageReceiver(allocator, stream.reader());
    var sender = messageSender(stream.writer());

    try sender.tversion(std.math.maxInt(u32), proto);

    const rversion = try iter.next();
    defer rversion.deinit();

    std.debug.print("Sizeof: {d}\n", .{ @sizeOf(Message) });

    inline for (std.meta.fields(Message.Command)) |field| {
        std.debug.print("{s}: {d}\n", .{ field.name, @sizeOf(field.type) });
    }

    std.debug.print("rversion: {any}\n", .{ rversion });
}

pub fn messageSender(writer: anytype) MessageSender(@TypeOf(writer)) {
    return MessageSender(@TypeOf(writer)).init(writer);
}

pub fn MessageSender(comptime Writer: type) type {
    return struct {
        writer: Writer,

        const Self = @This();

        pub fn init(writer: Writer) Self {
            return .{ .writer = writer };
        }

        pub fn tversion(self: Self, msize: u32, version: []const u8) !void {
            const msg = Message{
                .tag = NOTAG,
                .command = .{
                    .tversion = .{
                        .msize = msize,
                        .version = version,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rversion(self: Self, msize: u32, version: []const u8) !void {
            const msg = Message{
                .tag = NOTAG,
                .command = .{
                    .rversion = .{
                        .msize = msize,
                        .version = version,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tauth(self: Self, tag: u16, afid: u32, uname: []const u8, aname: []const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tauth = .{
                        .afid = afid,
                        .uname = uname,
                        .aname = aname,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rauth(self: Self, tag: u16, aqid: Qid) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rauth = .{
                        .aqid = aqid,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tattach(self: Self, tag: u16, fid: u32, afid: u32, uname: []const u8, aname: []const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tattach = .{
                        .fid = fid,
                        .afid = afid,
                        .uname = uname,
                        .aname = aname,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rattach(self: Self, tag: u16, qid: Qid) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rattach = .{
                        .qid = qid,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rerror(self: Self, tag: u16, ename: []const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rerror = .{
                        .ename = ename,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tflush(self: Self, tag: u16, oldtag: u16) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tflush = .{
                        .oldtag = oldtag,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn twalk(self: Self, tag: u16, fid: u32, newfid: u32, wname: [][]const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .twalk = .{
                        .fid = fid,
                        .newfid = newfid,
                        .wname = wname,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rwalk(self: Self, tag: u16, wqid: []Qid) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rwalk = .{
                        .wqid = wqid,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn topen(self: Self, tag: u16, fid: u32, mode: OpenMode) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .topen = .{
                        .fid = fid,
                        .mode = mode,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn ropen(self: Self, tag: u16, qid: Qid, iounit: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .ropen = .{
                        .qid = qid,
                        .iounit = iounit,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tcreate(self: Self, tag: u16, fid: u32, name: []const u8, perm: DirMode, mode: OpenMode) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tcreate = .{
                        .fid = fid,
                        .name = name,
                        .perm = perm,
                        .mode = mode,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rcreate(self: Self, tag: u16, qid: Qid, iounit: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rcreate = .{
                        .qid = qid,
                        .iounit = iounit,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tread(self: Self, tag: u16, fid: u32, offset: u64, count: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tread = .{
                        .fid = fid,
                        .offset = offset,
                        .count = count,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rread(self: Self, tag: u16, data: []const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rread = .{
                        .data = data,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn twrite(self: Self, tag: u16, fid: u32, offset: u64, data: []const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .twrite = .{
                        .fid = fid,
                        .offset = offset,
                        .data = data,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rwrite(self: Self, tag: u16, count: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rwrite = .{
                        .count = count,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tclunk(self: Self, tag: u16, fid: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tclunk = .{
                        .fid = fid,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tremove(self: Self, tag: u16, fid: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tremove = .{
                        .fid = fid,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn tstat(self: Self, tag: u16, fid: u32) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tstat = .{
                        .fid = fid,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn rstat(self: Self, tag: u16, stat: Stat) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .rstat = .{
                        .stat = stat,
                    }
                }
            };
            try msg.dump(self.writer);
        }

        pub fn twstat(self: Self, tag: u16, fid: u32, stat: Stat) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .twstat = .{
                        .fid = fid,
                        .stat = stat,
                    }
                }
            };
            try msg.dump(self.writer);
        }
    };
}

pub fn messageReceiver(allocator: mem.Allocator, reader: anytype) MessageReceiver(@TypeOf(reader)) {
    return MessageReceiver(@TypeOf(reader)).init(allocator, reader);
}

pub fn MessageReceiver(comptime Reader: type) type {
    return struct {
        allocator: mem.Allocator,
        reader: Reader,

        const Self = @This();

        pub fn init(allocator: mem.Allocator, reader: Reader) Self {
            return Self{ .allocator = allocator, .reader = reader };
        }

        pub fn next(self: Self) !Message {
            var counting = io.countingReader(self.reader);
            const size = try counting.reader().readIntLittle(u32);
            var limited = io.limitedReader(counting.reader(), size - 4);
            const internal_reader = limited.reader();

            const command = @intToEnum(Message.CommandEnum, try internal_reader.readByte());
            const tag = try internal_reader.readIntLittle(u16);

            var arena = std.heap.ArenaAllocator.init(self.allocator);
            errdefer arena.deinit();

            const comm: Message.Command = switch (command) {
                .tversion => try Message.Command.Tversion.parse(arena.allocator(), internal_reader),
                .rversion => try Message.Command.Rversion.parse(arena.allocator(), internal_reader),
                .tauth    => try Message.Command.Tauth.parse(arena.allocator(), internal_reader),
                .rauth    => try Message.Command.Rauth.parse(internal_reader),
                .tattach  => try Message.Command.Tattach.parse(arena.allocator(), internal_reader),
                .rattach  => try Message.Command.Rattach.parse(internal_reader),
                .terror   => Message.Command.terror,
                .rerror   => try Message.Command.Rerror.parse(arena.allocator(), internal_reader),
                .tflush   => try Message.Command.Tflush.parse(internal_reader),
                .rflush   => Message.Command.rflush,
                .twalk    => try Message.Command.Twalk.parse(arena.allocator(), internal_reader),
                .rwalk    => try Message.Command.Rwalk.parse(arena.allocator(), internal_reader),
                .topen    => try Message.Command.Topen.parse(internal_reader),
                .ropen    => try Message.Command.Ropen.parse(internal_reader),
                .tcreate  => try Message.Command.Tcreate.parse(arena.allocator(), internal_reader),
                .rcreate  => try Message.Command.Rcreate.parse(internal_reader),
                .tread    => try Message.Command.Tread.parse(internal_reader),
                .rread    => try Message.Command.Rread.parse(arena.allocator(), internal_reader),
                .twrite   => try Message.Command.Twrite.parse(arena.allocator(), internal_reader),
                .rwrite   => try Message.Command.Rwrite.parse(internal_reader),
                .tclunk   => try Message.Command.Tclunk.parse(internal_reader),
                .rclunk   => Message.Command.rclunk,
                .tremove  => try Message.Command.Tremove.parse(internal_reader),
                .rremove  => Message.Command.rremove,
                .tstat    => try Message.Command.Tstat.parse(internal_reader),
                .rstat    => try Message.Command.Rstat.parse(arena.allocator(), internal_reader),
                .twstat   => try Message.Command.Twstat.parse(arena.allocator(), internal_reader),
                .rwstat   => Message.Command.rwstat,
            };

            if (counting.bytes_read > size) {
                return error.MessageTooLarge;
            } else if (counting.bytes_read < size) {
                return error.MessageTooSmall;
            }

            return Message{
                .arena = arena,
                .tag = tag,
                .command = comm,
            };
        }
    };
}

pub fn parseWireString(allocator: mem.Allocator, reader: anytype) ![]const u8 {
    const size = try reader.readIntLittle(u16);
    return try reader.readAllAlloc(allocator, size);
}

pub fn dumpWireString(string: []const u8, writer: anytype) !void {
    if (string.len > std.math.maxInt(u16)) {
        return error.StringTooLarge;
    }
    try writer.writeIntLittle(u16, @intCast(u16, string.len));
    try writer.writeAll(string);
}

// const Command = enum(u8) {
//     Tversion = 100,
//     Rversion = 101,
//     Tauth = 102,
//     Rauth = 103,
//     Tattach = 104,
//     Rattach = 105,
//     Terror = 106,
//     Rerror = 107,
//     Tflush = 108,
//     Rflush = 109,
//     Twalk = 110,
//     Rwalk = 111,
//     Topen = 112,
//     Ropen = 113,
//     Tcreate = 114,
//     Rcreate = 115,
//     Tread = 116,
//     Rread = 117,
//     Twrite = 118,
//     Rwrite = 119,
//     Tclunk = 120,
//     Rclunk = 121,
//     Tremove = 122,
//     Rremove = 123,
//     Tstat = 124,
//     Rstat = 125,
//     Twstat = 126,
//     Rwstat = 127
// };

const Error = enum([]const u8) {
    badoffset = "bad offset",
    botch = "9P protocol botch",
    createnondir = "create in non-directory",
    dupfid = "duplicate fid",
    duptag = "duplicate tag",
    isdir = "is a directory",
    nocreate = "create prohibited",
    noremove = "remove prohibited",
    nostat = "stat prohibited",
    notfound = "file not found",
    nowstat = "wstat prohibited",
    perm = "permission denied",
    unknownfid = "unknown fid",
    baddir = "bad directory in wstat",
    walknotdir = "walk in non-directory",
    open = "file not open",
};

/// max elements for Twalk/Rwalk
const MAXWELEM = 16;
const NOTAG = ~@as(u16, 0);
const NOFID = ~@as(u32, 0);

pub const Message = struct {
    arena: ?std.heap.ArenaAllocator = null,
    tag: u16,
    command: Command,

    pub fn deinit(self: Message) void {
        if (self.arena) |arena| {
            arena.deinit();
        }
    }

    pub fn size(self: Message) !usize {
        return 4 + 1 + 2 + try self.command.size();
    }

    pub fn dump(self: Message, writer: anytype) !void {
        const msg_size = try self.size();
        if (msg_size > math.maxInt(u32)) {
            return error.MessageTooLarge;
        }
        try writer.writeIntLittle(u32, @intCast(u32, msg_size));
        try writer.writeByte(@enumToInt(self.command));
        try writer.writeIntLittle(u16, self.tag);
        try self.command.dump(writer);
    }

    pub const CommandEnum = @typeInfo(Command).Union.tag_type.?;

    pub const Command = union(enum(u8)) {
        tversion: Tversion = 100,
        rversion: Rversion = 101,
        tauth: Tauth = 102,
        rauth: Rauth = 103,
        tattach: Tattach = 104,
        rattach: Rattach = 105,
        /// Not allowed
        terror = 106,
        rerror: Rerror = 107,
        tflush: Tflush = 108,
        rflush = 109,
        twalk: Twalk = 110,
        rwalk: Rwalk = 111,
        topen: Topen = 112,
        ropen: Ropen = 113,
        tcreate: Tcreate = 114,
        rcreate: Rcreate = 115,
        tread: Tread = 116,
        rread: Rread = 117,
        twrite: Twrite = 118,
        rwrite: Rwrite = 119,
        tclunk: Tclunk = 120,
        rclunk = 121,
        tremove: Tremove = 122,
        rremove = 123,
        tstat: Tstat = 124,
        rstat: Rstat = 125,
        twstat: Twstat = 126,
        rwstat = 127,

        pub fn size(self: Command) !usize {
            var counting = io.countingWriter(io.null_writer);
            try self.dump(counting.writer());
            return counting.bytes_written;
        }

        pub fn dump(self: Command, writer: anytype) !void {
            switch (self) {
                .terror, .rflush, .rclunk, .rremove, .rwstat => {},
                inline else => |val| try val.dump(writer),
            }
        }

        pub const Tversion = struct {
            msize: u32,
            version: []const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .tversion = .{
                        .msize = try reader.readIntLittle(u32),
                        .version = try parseWireString(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Tversion, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.msize);
                try dumpWireString(self.version, writer);
            }
        };

        pub const Rversion = struct {
            msize: u32,
            version: []const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .rversion = .{
                        .msize = try reader.readIntLittle(u32),
                        .version = try parseWireString(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Rversion, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.msize);
                try dumpWireString(self.version, writer);
            }
        };

        pub const Tauth = struct {
            afid: u32,
            uname: []const u8,
            aname: []const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .tauth = .{
                        .afid = try reader.readIntLittle(u32),
                        .uname = try parseWireString(allocator, reader),
                        .aname = try parseWireString(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Tauth, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.afid);
                try dumpWireString(self.uname, writer);
                try dumpWireString(self.aname, writer);
            }
        };

        pub const Rauth = struct {
            aqid: Qid,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .rauth = .{
                        .aqid = try Qid.parse(reader),
                    }
                };
            }

            pub fn dump(self: Rauth, writer: anytype) !void {
                try self.aqid.dump(writer);
            }
        };

        pub const Tattach = struct {
            fid: u32,
            afid: u32,
            uname: []const u8,
            aname: []const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .tattach = .{
                        .fid = try reader.readIntLittle(u32),
                        .afid = try reader.readIntLittle(u32),
                        .uname = try parseWireString(allocator, reader),
                        .aname = try parseWireString(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Tattach, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
                try writer.writeIntLittle(u32, self.afid);
                try dumpWireString(self.uname, writer);
                try dumpWireString(self.aname, writer);
            }
        };

        pub const Rattach = struct {
            qid: Qid,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .rattach = .{
                        .qid = try Qid.parse(reader),
                    }
                };
            }

            pub fn dump(self: Rattach, writer: anytype) !void {
                try self.qid.dump(writer);
            }
        };

        pub const Rerror = struct {
            ename: []const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .rerror = .{
                        .ename = try parseWireString(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Rerror, writer: anytype) !void {
                try dumpWireString(self.ename, writer);
            }
        };

        pub const Tflush = struct {
            oldtag: u16,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .tflush = .{
                        .oldtag = try reader.readIntLittle(u16),
                    }
                };
            }

            pub fn dump(self: Tflush, writer: anytype) !void {
                try writer.writeIntLittle(u16, self.oldtag);
            }
        };

        pub const Twalk = struct {
            fid: u32,
            newfid: u32,
            wname: [][]const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                var wnames = std.ArrayList([]const u8).init(allocator);
                // would errdefer if not using arena
                const fid = try reader.readIntLittle(u32);
                const newfid = try reader.readIntLittle(u32);
                const nwname = try reader.readIntLittle(u16);
                for (0..nwname) |_| {
                    const name = try parseWireString(allocator, reader);
                    try wnames.append(name);
                }

                return .{
                    .twalk = .{
                        .fid = fid,
                        .newfid = newfid,
                        .wname = try wnames.toOwnedSlice(),
                    }
                };
            }

            pub fn dump(self: Twalk, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
                try writer.writeIntLittle(u32, self.newfid);
                try writer.writeIntLittle(u16, @intCast(u16, self.wname.len));
                for (self.wname) |name| {
                    try dumpWireString(name, writer);
                }
            }
        };

        pub const Rwalk = struct {
            wqid: []Qid,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                var qids = std.ArrayList(Qid).init(allocator);

                const nwqid = try reader.readIntLittle(u16);
                for (0..nwqid) |_| {
                    const qid = try Qid.parse(reader);
                    try qids.append(qid);
                }

                return .{
                    .rwalk = .{
                        .wqid = try qids.toOwnedSlice(),
                    }
                };
            }

            pub fn dump(self: Rwalk, writer: anytype) !void {
                try writer.writeIntLittle(u16, @intCast(u16, self.wqid.len));
                for (self.wqid) |qid| {
                    try qid.dump(writer);
                }
            }
        };

        pub const Topen = struct {
            fid:  u32,
            mode: OpenMode,

            pub fn parse(reader: anytype) !Command {
                const fid = try reader.readIntLittle(u32);
                const open_mode = @bitCast(OpenMode, try reader.readByte());

                return .{
                    .topen = .{
                        .fid = fid,
                        .mode = open_mode,
                    }
                };
            }

            pub fn dump(self: Topen, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
                try writer.writeByte(@bitCast(u8, self.mode));
            }
        };

        pub const Ropen = struct {
            qid: Qid,
            iounit: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .ropen = .{
                        .qid = try Qid.parse(reader),
                        .iounit = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Ropen, writer: anytype) !void {
                try self.qid.dump(writer);
                try writer.writeIntLittle(u32, self.iounit);
            }
        };

        pub const Tcreate = struct {
            fid: u32,
            name: []const u8,
            perm: DirMode,
            mode: OpenMode,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .tcreate = .{
                        .fid = try reader.readIntLittle(u32),
                        .name = try parseWireString(allocator, reader),
                        .perm = @bitCast(DirMode, try reader.readIntLittle(u32)),
                        .mode = @bitCast(OpenMode, try reader.readByte()),
                    }
                };
            }

            pub fn dump(self: Tcreate, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
                try dumpWireString(self.name, writer);
                try writer.writeIntLittle(u32, @bitCast(u32, self.perm));
                try writer.writeByte(@bitCast(u8, self.mode));
            }
        };

        pub const Rcreate = struct {
            qid: Qid,
            iounit: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .rcreate = .{
                        .qid = try Qid.parse(reader),
                        .iounit = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Rcreate, writer: anytype) !void {
                try self.qid.dump(writer);
                try writer.writeIntLittle(u32, self.iounit);
            }
        };

        pub const Tread = struct {
            fid: u32,
            offset: u64,
            count: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .tread = .{
                        .fid = try reader.readIntLittle(u32),
                        .offset = try reader.readIntLittle(u64),
                        .count = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Tread, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
                try writer.writeIntLittle(u64, self.offset);
                try writer.writeIntLittle(u32, self.count);
            }
        };

        pub const Rread = struct {
            data: []const u8,

            // TODO: Not very efficient, use proper reader/writer
            // interface for receiving large amounts of data instead
            // of allocating on heap.
            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                const count = try reader.readIntLittle(u32);
                var data = try allocator.alloc(u8, count);
                const data_size = try reader.readAll(data);
                if (data_size != count) {
                    return error.IncorrectCount;
                }

                return .{
                    .rread = .{
                        .data = data,
                    }
                };
            }

            pub fn dump(self: Rread, writer: anytype) !void {
                if (self.data.len > math.maxInt(u32)) {
                    return error.DataTooLong;
                }
                try writer.writeIntLittle(u32, @intCast(u32, self.data.len));
                try writer.writeAll(self.data);
            }
        };

        pub const Twrite = struct {
            fid: u32,
            offset: u64,
            data: []const u8,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                const fid = try reader.readIntLittle(u32);
                const offset = try reader.readIntLittle(u64);
                const count = try reader.readIntLittle(u32);
                var data = try allocator.alloc(u8, count);
                const data_size = try reader.readAll(data);
                if (data_size != count) {
                    return error.IncorrectCount;
                }

                return .{
                    .twrite = .{
                        .fid = fid,
                        .offset = offset,
                        .data = data,
                    }
                };
            }

            pub fn dump(self: Twrite, writer: anytype) !void {
                if (self.data.len > math.maxInt(u32)) {
                    return error.DataTooLong;
                }

                try writer.writeIntLittle(u32, self.fid);
                try writer.writeIntLittle(u64, self.offset);
                try writer.writeIntLittle(u32, @intCast(u32, self.data.len));
                try writer.writeAll(self.data);
            }
        };

        pub const Rwrite = struct {
            count: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .rwrite = .{
                        .count = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Rwrite, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.count);
            }
        };

        pub const Tclunk = struct {
            fid: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .tclunk = .{
                        .fid = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Tclunk, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
            }
        };

        pub const Tremove = struct {
            fid: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .tremove = .{
                        .fid = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Tremove, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
            }
        };

        pub const Tstat = struct {
            fid: u32,

            pub fn parse(reader: anytype) !Command {
                return .{
                    .tstat = .{
                        .fid = try reader.readIntLittle(u32),
                    }
                };
            }

            pub fn dump(self: Tstat, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
            }
        };

        pub const Rstat = struct {
            stat: Stat,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .rstat = .{
                        .stat = try Stat.parse(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Rstat, writer: anytype) !void {
                try self.stat.dump(writer);
            }
        };

        pub const Twstat = struct {
            fid: u32,
            stat: Stat,

            pub fn parse(allocator: mem.Allocator, reader: anytype) !Command {
                return .{
                    .twstat = .{
                        .fid = try reader.readIntLittle(u32),
                        .stat = try Stat.parse(allocator, reader),
                    }
                };
            }

            pub fn dump(self: Twstat, writer: anytype) !void {
                try writer.writeIntLittle(u32, self.fid);
                try self.stat.dump(writer);
            }
        };
    };
};

const Qid = struct {
    path: u64,
    vers: u32,
    qtype: QType,

    pub fn parse(reader: anytype) !Qid {
        return Qid{
            .path = try reader.readIntLittle(u64),
            .vers = try reader.readIntLittle(u32),
            .qtype = @intToEnum(QType, try reader.readByte()),
        };
    }

    pub fn dump(self: Qid, writer: anytype) !void {
        try writer.writeIntLittle(u64, self.path);
        try writer.writeIntLittle(u32, self.vers);
        try writer.writeByte(@enumToInt(self.qtype));
    }

    const QType = enum(u8) {
        /// type bit for directories
        dir = 0x80,
        /// type bit for append only files
        append = 0x40,
        /// type bit for exclusive use files
        excl = 0x20,
        /// type bit for mounted channel
        mount = 0x10,
        /// type bit for authentication file
        auth = 0x08,
        /// plain file
        file = 0x00
    };
};

const OpenMode = packed struct(u8) {
    /// open permissions
    perm: Permissions = .read,
    _padding: u1 = 0,
    /// (except for exec), truncate file first
    trunc: bool = false,
    /// close on exec
    cexec: bool = false,
    /// remove on close
    rclose: bool = false,
    /// direct access
    direct: bool = false,

    const Permissions = enum(u3) {
        /// open for read
        read = 0,
        /// write
        write = 1,
        /// read and write
        rdwr = 2,
        /// read, write, execute
        exec = 3
    };

    const Values = enum(u16) {
        read = 0,         // open for read
        write = 1,        // write
        rdwr = 2,         // read and write
        exec = 3,         // execute, == read but check execute permission
        trunc = 16,       // or'ed in (except for exec), truncate file first
        cexec = 32,       // or'ed in, close on exec
        rclose = 64,      // or'ed in, remove on close
        direct = 128,     // or'ed in, direct access
        nonblock = 256,   // or'ed in, non-blocking call
        excl = 0x1000,    // or'ed in, exclusive use (create only)
        lock = 0x2000,    // or'ed in, lock after opening
        append = 0x4000,  // or'ed in, append only
    };
};

test "open mode is correct" {
    try testing.expectEqual(@enumToInt(OpenMode.Values.read), @bitCast(u8, OpenMode{ .perm = .read  }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.write), @bitCast(u8, OpenMode{ .perm = .write  }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.rdwr), @bitCast(u8, OpenMode{ .perm = .rdwr  }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.exec), @bitCast(u8, OpenMode{ .perm = .exec  }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.read), @bitCast(u8, OpenMode{ }));

    try testing.expectEqual(@enumToInt(OpenMode.Values.trunc), @bitCast(u8, OpenMode{ .trunc = true }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.cexec), @bitCast(u8, OpenMode{ .cexec = true }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.rclose), @bitCast(u8, OpenMode{ .rclose = true }));
    try testing.expectEqual(@enumToInt(OpenMode.Values.direct), @bitCast(u8, OpenMode{ .direct = true }));
}

const DirMode = packed struct(u32) {
    /// mode bit for execute permission
    exec: bool = false,
    /// mode bit for write permission
    write: bool = false,
    /// mode bit for read permission
    read: bool = false,
    _padding1: u13 = 0,
    /// mode bit for sticky bit (Unix, 9P2000.u)
    sticky: bool = false,
    _padding2: u1 = 0,
    /// mode bit for setgid (Unix, 9P2000.u)
    setgid: bool = false,
    /// mode bit for setuid (Unix, 9P2000.u)
    setuid: bool = false,
    /// mode bit for socket (Unix, 9P2000.u)
    socket: bool = false,
    /// mode bit for named pipe (Unix, 9P2000.u)
    namedpipe: bool = false,
    _padding4: u1 = 0,
    /// mode bit for device file (Unix, 9P2000.u)
    device: bool = false,
    _padding5: u1 = 0,
    /// mode bit for symbolic link (Unix, 9P2000.u)
    symlink: bool = false,
    /// mode bit for non-backed-up file
    tmp: bool = false,
    /// mode bit for authentication file
    auth: bool = false,
    /// mode bit for mounted channel
    mount: bool = false,
    /// mode bit for exclusive use files,
    excl: bool = false,
    /// mode bit for append only files
    append: bool = false,
    /// mode bit for directories
    dir: bool = false,

    const Values = enum(u32) {
        dir = 0x80000000,
        append = 0x40000000,
        excl = 0x20000000,
        mount = 0x10000000,
        auth = 0x08000000,
        tmp = 0x04000000,
        symlink = 0x02000000,
        device = 0x00800000,
        namedpipe = 0x00200000,
        socket = 0x00100000,
        setuid = 0x00080000,
        setgid = 0x00040000,
        sticky = 0x00010000,

        read = 0x4,
        write = 0x2,
        exec = 0x1,
    };
};

test "bitlengths are good" {
    try testing.expectEqual(@enumToInt(DirMode.Values.exec), @bitCast(u32, DirMode{ .exec = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.write), @bitCast(u32, DirMode{ .write = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.read), @bitCast(u32, DirMode{ .read = true }));

    try testing.expectEqual(@enumToInt(DirMode.Values.sticky), @bitCast(u32, DirMode{ .sticky = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.setgid), @bitCast(u32, DirMode{ .setgid = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.setuid), @bitCast(u32, DirMode{ .setuid = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.socket), @bitCast(u32, DirMode{ .socket = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.namedpipe), @bitCast(u32, DirMode{ .namedpipe = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.device), @bitCast(u32, DirMode{ .device = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.symlink), @bitCast(u32, DirMode{ .symlink = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.tmp), @bitCast(u32, DirMode{ .tmp = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.auth), @bitCast(u32, DirMode{ .auth = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.mount), @bitCast(u32, DirMode{ .mount = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.excl), @bitCast(u32, DirMode{ .excl = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.append), @bitCast(u32, DirMode{ .append = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.dir), @bitCast(u32, DirMode{ .dir = true }));
}

const Stat = struct {
    pkt_size: u16,
    stype: u16,
    dev: u32,
    qid: Qid,
    mode: u32,
    atime: u32,
    mtime: u32,
    length: u64,
    name: []const u8,
    uid: []const u8,
    gid: []const u8,
    muid: []const u8,

    pub fn parse(allocator: mem.Allocator, reader: anytype) !Stat {
        const pkt_size = try reader.readIntLittle(u16);
        const stype = try reader.readIntLittle(u16);
        const dev = try reader.readIntLittle(u32);
        const qid_type = try reader.readByte();
        const qid_vers = try reader.readIntLittle(u32);
        const qid_path = try reader.readIntLittle(u64);
        const qid = Qid{
            .qtype = @intToEnum(Qid.QType, qid_type),
            .vers = qid_vers,
            .path = qid_path,
        };
        const mode = try reader.readIntLittle(u32);
        const atime = try reader.readIntLittle(u32);
        const mtime = try reader.readIntLittle(u32);
        const length = try reader.readIntLittle(u64);
        const name = try parseWireString(allocator, reader);
        const uid = try parseWireString(allocator, reader);
        const gid = try parseWireString(allocator, reader);
        const muid = try parseWireString(allocator, reader);
        return .{
            .pkt_size = pkt_size,
            .stype = stype,
            .dev = dev,
            .qid = qid,
            .mode = mode,
            .atime = atime,
            .mtime = mtime,
            .length = length,
            .name = name,
            .uid = uid,
            .gid = gid,
            .muid = muid,
        };
    }

    pub fn dump(self: Stat, writer: anytype) !void {
        if (self.size() > math.maxInt(u16)) {
            return error.StatTooLarge;
        }
        try writer.writeIntLittle(u16, @intCast(u16, self.size()));
        try writer.writeIntLittle(u16, self.stype);
        try writer.writeIntLittle(u32, self.dev);
        try writer.writeByte(@enumToInt(self.qid.qtype));
        try writer.writeIntLittle(u32, self.qid.vers);
        try writer.writeIntLittle(u64, self.qid.path);
        try writer.writeIntLittle(u32, self.mode);
        try writer.writeIntLittle(u32, self.atime);
        try writer.writeIntLittle(u32, self.mtime);
        try writer.writeIntLittle(u64, self.length);
        try dumpWireString(self.name, writer);
        try dumpWireString(self.uid, writer);
        try dumpWireString(self.gid, writer);
        try dumpWireString(self.muid, writer);
    }

    pub fn size(self: Stat) usize {
        const qid = 1 + 4 + 8;
        const static = 2 + 2 + 4 + qid + 4 + 4 + 4 + 8;
        return static +
            self.name.len + 2 +
            self.uid.len + 2 +
            self.gid.len + 2 +
            self.muid.len + 2;
    }
};

test "ref all" {
    testing.refAllDeclsRecursive(@This());
}

// twalk
// https://www.omarpolo.com/post/taking-about-9p-open-and-walk.html

// The iounit field returned by open and create may be zero. If it is
// not, it is the maximum number of bytes that are guaranteed to be
// read from or written to the file without breaking the I/O transfer
// into multiple 9P messages; see read(5).

// // struct Qid
// {
// 	uvlong	path;  // very long = long long??
// 	ulong	vers;
// 	uchar	type;
// }; ????
// https://github.com/Harvey-OS/harvey/blob/bf084ee78de58b5f05b98235bb6e6887fde6e8c4/sys/src/9/port/lib.h#L190
// https://github.com/Harvey-OS/harvey/blob/bf084ee78de58b5f05b98235bb6e6887fde6e8c4/sys/include/fcall.h#L4

// https://ericvh.github.io/9p-rfc/rfc9p2000.html

// socat TCP4-LISTEN:5640,range=127.0.0.1/32 EXEC:"./u9fs -D -a none -u `whoami`"

// The notation string[s] (using a literal s character) is shorthand
// for s[2] followed by s bytes of UTF-8 text.

// little- endian order

// size[4] Tversion tag[2] msize[4] version[s]
// size[4] Rversion tag[2] msize[4] version[s]

// size[4] Tauth tag[2] afid[4] uname[s] aname[s]
// size[4] Rauth tag[2] aqid[13]

// size[4] Rerror tag[2] ename[s]

// size[4] Tflush tag[2] oldtag[2]
// size[4] Rflush tag[2]

// size[4] Tattach tag[2] fid[4] afid[4] uname[s] aname[s]
// size[4] Rattach tag[2] qid[13]

// size[4] Twalk tag[2] fid[4] newfid[4] nwname[2] nwname*(wname[s])
// size[4] Rwalk tag[2] nwqid[2] nwqid*(wqid[13])

// size[4] Topen tag[2] fid[4] mode[1]
// size[4] Ropen tag[2] qid[13] iounit[4]

// size[4] Tcreate tag[2] fid[4] name[s] perm[4] mode[1]
// size[4] Rcreate tag[2] qid[13] iounit[4]

// size[4] Tread tag[2] fid[4] offset[8] count[4]
// size[4] Rread tag[2] count[4] data[count]

// size[4] Twrite tag[2] fid[4] offset[8] count[4] data[count]
// size[4] Rwrite tag[2] count[4]

// size[4] Tclunk tag[2] fid[4]
// size[4] Rclunk tag[2]

// size[4] Tremove tag[2] fid[4]
// size[4] Rremove tag[2]

// size[4] Tstat tag[2] fid[4]
// size[4] Rstat tag[2] stat[n]

// size[4] Twstat tag[2] fid[4] stat[n]
// size[4] Rwstat tag[2]
