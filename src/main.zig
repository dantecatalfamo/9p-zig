const std = @import("std");
const io = std.io;
const mem = std.mem;

pub fn main() !void {
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

const Command = enum(u8) {
    Tversion = 100,
    Rversion = 101,
    Tauth = 102,
    Rauth = 103,
    Tattach = 104,
    Rattach = 105,
    Terror = 106,
    Rerror = 107,
    Tflush = 108,
    Rflush = 109,
    Twalk = 110,
    Rwalk = 111,
    Topen = 112,
    Ropen = 113,
    Tcreate = 114,
    Rcreate = 115,
    Tread = 116,
    Rread = 117,
    Twrite = 118,
    Rwrite = 119,
    Tclunk = 120,
    Rclunk = 121,
    Tremove = 122,
    Rremove = 123,
    Tstat = 124,
    Rstat = 125,
    Twstat = 126,
    Rwstat = 127
};

const MAXWELEM = 16; // max elements for Twalk/Rwalk
const NOTAG: u16 = ~0;
const NOFID: u32 = ~0;

const Message = struct {
    size: u32,
    tag: u16,
    command:  union(enum(u8)) {
        Tversion: struct {
            msize: u32,
            version: []const u8
        } = 100,
        Rversion: struct {
            msize: u32,
            version: []const u8
        } = 101,

        Tauth: struct {
            afid: u32,
            uname: []const u8,
            aname: []const u8
        } = 102,
        Rauth: struct {
            aqid: Qid
        } = 103,

        Tattach: struct {
            fid: u32,
            afid: u32,
            uname: []const u8,
            aname: []const u8
        } = 104,
        Rattach: struct {
            qid: Qid
        } = 105,

        Terror = 106, // Not allowed
        Rerror: struct {
            ename: []const u8
        } = 107,

        Tflush: struct {
            oldtag: u16
        } = 108,
        Rflush = 109,

        Twalk: struct {
            fid: u32,
            newfid: u32,
            nwname: u16,
            wname: [][]const u8
        } = 110,
        Rwalk: struct {
            nwqid: u16,
            wqid: []Qid
        } = 111,

        Topen: struct {
            fid:  u32,
            mode: u8
        } = 112,
        Ropen: struct {
            qid: Qid,
            iounit: u32
        } = 113,

        Tcreate: struct {
            fid: u32,
            name: []const u8,
            perm: u32,
            mode: u8
        } = 114,
        Rcreate: struct {
            qid: Qid,
            iounit: u32,
        } = 115,

        Tread: struct {
            fid: u32,
            offset: u64,
            count: u32
        } = 116,
        Rread: struct {
            count: u32,
            data: []const u8
        } = 117,

        Twrite: struct {
            fid: u32,
            offset: u64,
            count: u32,
            data: []const u8
        } = 118,
        Rwrite: struct {
            count: u32
        } = 119,

        Tclunk: struct {
            fid: u32,
        } = 120,
        Rclunk = 121,
        Tremove: struct {
            fid: u32
        } = 122,
        Rremove = 123,

        Tstat: struct {
            fid: u32
        } = 124,
        Rstat: struct {
            stat: Stat
        } = 125,

        Twstat: struct {
            fid: u32,
            stat: Stat
        } = 126,
        Rwstat = 127
    }
};

const Qid = struct {
    path: u64,
    vers: u32,
    qtype: QType
};

const QType = enum(u8) {
    // type bit for directories
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

    pub fn parse(data: []const u8) !Stat {
        var buffer = std.io.fixedBufferStream(data);
        const reader = buffer.reader();

        return Stat{
            .size
        };
    }
};

pub fn parseWireString(data: std.fs.File.Reader) ![]const u8 {
    const size = data.readIntLittle(u16);
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
