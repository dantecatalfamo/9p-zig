const std = @import("std");
const io = std.io;
const mem = std.mem;
const testing = std.testing;

pub fn main() !void {
    const addr = "127.0.0.1:564";
    _ = addr;
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

const proto = "9p2000";

pub fn parse(allocator: mem.Allocator, in_reader: std.fs.File.Reader) !Message {
    const size = try in_reader.readIntLittle(u32);
    var limited_reader = std.io.limitedReader(in_reader, size - 4);
    const reader = limited_reader.reader();
    const cmd = try reader.readByte();
    const command = @intToEnum(Message.CommandEnum, cmd);
    const tag = try reader.readIntLittle(u16);

    const comm: Message.Command = switch (command) {
        .tversion => .{
            .tversion = .{
                .msize = try reader.readIntLittle(u32),
                .version = try parseWireString(allocator, reader),
            }
        },
        // .rversion => .rversion{
        //         .msize = try reader.readIntLittle(u32),
        //         .version = try parseWireString(allocator, reader),
        // },
        else => Message.Command.terror,
    };

    return Message{
        .total_size = size,
        .tag = tag,
        .command = comm,
    };
}

pub fn dump(message: Message, writer: std.fs.File.Writer) !void {
    try writer.writeIntLittle(u32, message.size());
    try writer.writeByte(@enumToInt(message.command));
    try writer.writeIntLittle(u16, message.tag);
}

pub fn parseWireString(allocator: mem.Allocator, data: anytype) ![]const u8 {
    const size = try data.readIntLittle(u16);
    return try data.readAllAlloc(allocator, size);
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
const NOTAG: u16 = ~0;
const NOFID: u32 = ~0;

pub const Message = struct {
    total_size: u32,
    tag: u16,
    command: Command,

    pub fn size(self: Message) u32 {
        return 4 + 1 + 2 + self.command.size();
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

        pub const Tversion = struct {
            msize: u32,
            version: []const u8,

            pub fn size(self: Tversion) usize {
                return 4 + @sizeOf(u16) + self.version.len;
            }
        };

        pub const Rversion = struct {
            msize: u32,
            version: []const u8,

            pub fn size(self: Rversion) usize {
                return 4 + @sizeOf(u16) + self.version.len;
            }
        };

        pub const Tauth = struct {
            afid: u32,
            uname: []const u8,
            aname: []const u8
        };

        pub const Rauth = struct {
            aqid: Qid
        };

        pub const Tattach = struct {
            fid: u32,
            afid: u32,
            uname: []const u8,
            aname: []const u8
        };

        pub const Rattach = struct {
            qid: Qid
        };

        pub const Rerror = struct {
            ename: []const u8
        };

        pub const Tflush = struct {
            oldtag: u16
        };

        pub const Twalk = struct {
            fid: u32,
            newfid: u32,
            nwname: u16,
            wname: [][]const u8
        };

        pub const Rwalk = struct {
            nwqid: u16,
            wqid: []Qid
        };

        pub const Topen = struct {
            fid:  u32,
            mode: u8
        };

        pub const Ropen = struct {
            qid: Qid,
            iounit: u32
        };

        pub const Tcreate = struct {
            fid: u32,
            name: []const u8,
            perm: u32,
            mode: u8
        };

        pub const Rcreate = struct {
            qid: Qid,
            iounit: u32,
        };

        pub const Tread = struct {
            fid: u32,
            offset: u64,
            count: u32
        };

        pub const Rread = struct {
            count: u32,
            data: []const u8
        };

        pub const Twrite = struct {
            fid: u32,
            offset: u64,
            count: u32,
            data: []const u8
        };

        pub const Rwrite = struct {
            count: u32
        };

        pub const Tclunk = struct {
            fid: u32,
        };

        pub const Tremove = struct {
            fid: u32
        };

        pub const Tstat = struct {
            fid: u32
        };

        pub const Rstat = struct {
            stat: Stat
        };

        pub const Twstat = struct {
            fid: u32,
            stat: Stat
        };

        pub fn size(self: Command) u32 {
            return switch (self) {
                .terror, .rflush, .rclunk, .rremove, .rwstat => 0,
                else => |val| val.size(),
            };
        }
    };
};

const Qid = struct {
    path: u64,
    vers: u32,
    qtype: QType
};

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

const OpenMode = enum(u16) {
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
    size: u16,
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

    // pub fn parse(data: []const u8) !Stat {
    //     var buffer = std.io.fixedBufferStream(data);
    //     const reader = buffer.reader();
    //     _ = reader;

    //     return Stat{
    //         .size
    //     };
    // }
};

test "ref all" {
    testing.refAllDeclsRecursive(@This());
}

// // struct Qid
// {
// 	uvlong	path;  // very long = long long??
// 	ulong	vers;
// 	uchar	type;
// }; ????
// https://github.com/Harvey-OS/harvey/blob/bf084ee78de58b5f05b98235bb6e6887fde6e8c4/sys/src/9/port/lib.h#L190
// https://github.com/Harvey-OS/harvey/blob/bf084ee78de58b5f05b98235bb6e6887fde6e8c4/sys/include/fcall.h#L4

// https://ericvh.github.io/9p-rfc/rfc9p2000.html

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
