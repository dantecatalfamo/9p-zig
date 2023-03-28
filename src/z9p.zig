const std = @import("std");
const io = std.io;
const mem = std.mem;
const math = std.math;
const testing = std.testing;

pub const proto = "9P2000";

pub fn simpleClient(allocator: mem.Allocator, reader: anytype, writer: anytype) SimpleClient(@TypeOf(reader), @TypeOf(writer)) {
    return SimpleClient(@TypeOf(reader), @TypeOf(writer)).init(allocator, reader, writer);
}

// Never sends parallel queries, so always reuses tag 0
pub fn SimpleClient(comptime Reader: type, comptime Writer: type) type {
    return struct {
        allocator: mem.Allocator,
        receiver: MessageReceiver(Reader),
        sender: MessageSender(Writer),

        ///  The client suggests a maximum message size, msize, that
        ///  is the maximum length, in bytes, it will ever generate or
        ///  expect to receive in a single 9P message. This count
        ///  includes all 9P protocol data, starting from the size
        ///  field and extending through the message, but excludes
        ///  enveloping transport protocols. The server responds with
        ///  its own maximum, msize, which must be less than or equal
        ///  to the client's value. Thenceforth, both sides of the
        ///  connection must honor this limit.
        msize: u32,
        handles: HandleList,

        const Self = @This();

        // We shouldn't have more than one or two open at a time, a list is fine.
        const HandleList = std.ArrayList(*Handle);


        pub fn init(allocator: mem.Allocator, reader: Reader, writer: Writer) Self {
            return .{
                .allocator = allocator,
                .receiver = messageReceiver(allocator, reader),
                .sender = messageSender(writer),
                .msize = 0,
                .handles = HandleList.init(allocator),
            };
        }

        pub fn getUnusedFid(self: *Self) u32 {
            var lowest_unused: u32 = 0;
            // FIXME: Assumes Fids are in order, which they probably
            // won't be... just a test
            for (self.handles.items) |handle| {
                if (handle.fid == lowest_unused) {
                    lowest_unused += 1;
                }
            }

            return lowest_unused;
        }

        // FIXME: Goes with above, idk if this will work it's almost 3am.
        pub fn setHandle(self: *Self, handle: Handle) !*Handle {
            const new_handle = try self.allocator.create(Handle);
            errdefer self.allocator.destroy(new_handle);
            new_handle.* = handle;

            var inserted = false;
            for (self.handles.items, 0..) |existing_handle, idx| {
                if (existing_handle.fid > handle.fid) {
                    try self.handles.insert(idx, new_handle);
                    inserted = true;
                }
            }

            if (!inserted) {
                try self.handles.append(new_handle);
            }
            return new_handle;
        }

        pub fn removeHandle(self: *Self, handle: *Handle) !void {
            var index: ?usize = null;

            for (self.handles.items, 0..) |hndl, idx| {
                if (hndl == handle) {
                    index = idx;
                }
            }

            if (index) |idx| {
                _ = self.handles.orderedRemove(idx);
                return;
            }

            return error.HandleDoesNotExist;
        }

        pub fn deinit(self: *Self) void {
            self.handles.deinit();
        }

        pub fn connect(self: *Self, msize: u32) !void {
            try self.sender.tversion(msize, proto);
            const msg = try self.receiver.next();
            defer msg.deinit();
            if (msg.command != .rversion) {
                return error.UnexpectedMessage;
            }
            self.msize = msg.command.rversion.msize;
        }

        pub fn auth(self: *Self, uname: []const u8, aname: []const u8) !*Handle {
            const afid = self.getUnusedFid();
            try self.sender.tauth(0, afid, uname, aname);
            const msg = try self.receiver.next();
            defer msg.deinit();

            if (msg.command != .rauth) {
                return error.UnexpectedMessage;
            }
            const handle = Handle{
                .client = self,
                .fid = afid,
                .qid = msg.command.rauth.aqid,
            };
            return try self.setHandle(handle);
        }

        pub fn attach(self: *Self, auth_handle: ?Handle, uname: []const u8, aname: []const u8) !*Handle {
            const fid = self.getUnusedFid();
            const afid = if (auth_handle) |a| a.fid else null;
            try self.sender.tattach(0, fid, afid, uname, aname);
            const msg = try self.receiver.next();
            defer msg.deinit();

            if (msg.command != .rattach) {
                return error.UnexpectedMessage;
            }
            const handle = Handle{
                .client = self,
                .fid = fid,
                .qid = msg.command.rattach.qid,
            };
            return try self.setHandle(handle);
        }

        pub fn flush(self: *Self) void {
            _ = self;
            // Since this client only ever has one message in flight
            // at once, this does nothing
        }

        const Handle = struct {
            client: *Self,
            fid: u32,
            qid: Qid,
            /// The iounit field returned by open and create may be
            /// zero. If it is not, it is the maximum number of bytes
            /// that are guaranteed to be read from or written to the
            /// file without breaking the I/O transfer into multiple
            /// 9P messages; see read(5).
            iounit: u32 = 0,
            pos: u64 = 0,
            opened: bool = false,

            pub fn deinit(self: *Handle) void {
                self.client.allocator.destroy(self);
            }

            pub fn format(self: Handle, comptime fmt: []const u8, options: std.fmt.FormatOptions, out_writer: anytype) !void {
                _ = fmt;
                _ = options;

                try out_writer.print("Handle{{ fid: {d}, qid: {any}, iounit: {d} }}", .{ self.fid, self.qid, self.iounit });
            }

            pub fn walk(self: Handle, path: []const []const u8) !*Handle {
                if (self.opened) {
                    return error.FileOpen;
                }
                const new_fid = self.client.getUnusedFid();
                try self.client.sender.twalk(0, self.fid, new_fid, path);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rwalk) {
                    return error.UnexpectedMessage;
                }
                const qid = if (msg.command.rwalk.wqid.len == 0)
                    self.qid
                else
                    msg.command.rwalk.wqid[msg.command.rwalk.wqid.len-1];

                const handle = Handle{
                    .client = self.client,
                    .fid = new_fid,
                    .qid = qid,
                };
                return try self.client.setHandle(handle);
            }

            /// After a file has been opened, further opens will fail until fid has been clunked.
            pub fn open(self: *Handle, mode: OpenMode) !void {
                if (self.opened) {
                    return error.FileOpen;
                }

                try self.client.sender.topen(0, self.fid, mode);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .ropen) {
                    return error.UnexpectedMessage;
                }

                self.qid = msg.command.ropen.qid;
                self.iounit = msg.command.ropen.iounit;
                self.opened = true;
            }

            /// Caller responsible for deinitializing returned Stat
            pub fn stat(self: *Handle) !Stat {
                try self.client.sender.tstat(0, self.fid);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rstat) {
                    return error.UnexpectedMessage;
                }

                return msg.command.rstat.stat.clone(self.client.allocator);
            }

            pub fn read(self: *Handle, buffer: []u8) !usize {
                const msize_max_data = self.client.msize - (4 + 1 + 2 + 4 + 13); // minus rread header data + a mysterious value
                const iounit_max_data = if (self.iounit != 0) self.iounit else math.maxInt(u32);
                const read_size_limit = @min(msize_max_data, iounit_max_data);
                const count = @min(read_size_limit, @intCast(u32, buffer.len));

                try self.client.sender.tread(0, self.fid, self.pos, count);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rread) {
                    return error.UnexpectedMessage;
                }

                const data_size = msg.command.rread.data.len;
                mem.copy(u8, buffer, msg.command.rread.data);
                self.pos += data_size;

                return data_size;
            }

            pub const ReadError = error{
                UnexpectedMessage,
                MessageTooLarge,
                StringTooLarge,
                DataTooLong,
                StatTooLarge,
                Rerror,
                EndOfStream,
                IncorrectStringSize,
                IncorrectCount
            } || Reader.Error || Writer.Error || mem.Allocator.Error; // @typeInfo(@typeInfo(@TypeOf(read)).Fn.return_type.?).ErrorUnion.error_set;

            pub const ClientReader = std.io.Reader(*Handle, ReadError, read);

            pub fn reader(self: *Handle) ClientReader {
                return .{ .context = self };
            }

            pub fn files(self: *Handle) !DirectoryList {
                self.pos = 0;

                const dir_data = try self.reader().readAllAlloc(self.client.allocator, math.maxInt(u32));
                defer self.client.allocator.free(dir_data);

                var dir_reader = std.io.fixedBufferStream(dir_data);

                var list = StatList.init(self.client.allocator);
                while (true) {
                    const s = Stat.parse(self.client.allocator, dir_reader.reader()) catch |err| switch (err) {
                        error.EndOfStream => {
                            break;
                        },
                        else => return err,
                    };
                    try list.append(s);
                }

                return DirectoryList{
                    .allocator = self.client.allocator,
                    .stats = try list.toOwnedSlice(),
                };
            }

            const StatList = std.ArrayList(Stat);

            const DirectoryList = struct {
                allocator: mem.Allocator,
                stats: []Stat,

                pub fn deinit(self: DirectoryList) void {
                    for (self.stats) |dir_stat| {
                        dir_stat.deinit();
                    }
                    self.allocator.free(self.stats);
                }
            };

            pub fn create(self: *Handle, name: []const u8, perm: DirMode, mode: OpenMode) !void {
                if (self.opened) {
                    // Creating a file in a directory whose fid you've
                    // opened fails
                    return error.FileOpen;
                }

                try self.client.sender.tcreate(0, self.fid, name, perm, mode);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rcreate) {
                    return error.UnexpectedMessage;
                }

                self.iounit = msg.command.rcreate.iounit;
                self.qid = msg.command.rcreate.qid;
            }

            /// Deletes the file associated with the handle, frees the handle
            pub fn remove(self: *Handle) !void {
                try self.client.sender.tremove(0, self.fid);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rremove) {
                    return error.UnexpectedMessage;
                }

                try self.client.removeHandle(self);
                self.deinit();
            }

            /// Tells the server this handle is no longer required,
            /// frees the handle
            pub fn clunk(self: *Handle) !void {
                try self.client.sender.tclunk(0, self.fid);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rclunk) {
                    return error.UnexpectedMessage;
                }

                try self.client.removeHandle(self);
                self.deinit();
            }

            pub fn wstat(self: *Handle, new_stat: Stat) !void {
                try self.client.sender.twstat(0, self.fid, new_stat);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rwstat) {
                    return error.UnexpectedMessage;
                }
            }

            pub fn write(self: *Handle, bytes: []const u8) !usize {
                const msize_max_data = self.client.msize - (4 + 1 + 2 + 4 + 8 + 4);
                const iounit_max_data = if (self.iounit != 0) self.iounit else math.maxInt(u32);
                const write_size_limit = @min(msize_max_data, iounit_max_data);
                const count = @min(write_size_limit, @intCast(u32, bytes.len));

                try self.client.sender.twrite(0, self.fid, self.pos, bytes[0..count]);
                const msg = try self.client.receiver.next();
                defer msg.deinit();

                if (msg.command != .rwrite) {
                    return error.UnexpectedMessage;
                }

                return msg.command.rwrite.count;
            }

            pub const WriteError = ReadError;

            pub const ClientWriter = std.io.Writer(*Handle, WriteError, write);

            pub fn writer(self: *Handle) ClientWriter {
                return .{ .context = self };
            }
        };
    };
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

        pub fn tattach(self: Self, tag: u16, fid: u32, afid: ?u32, uname: []const u8, aname: []const u8) !void {
            const msg = Message{
                .tag = tag,
                .command = .{
                    .tattach = .{
                        .fid = fid,
                        .afid = if (afid) |a| a else NOFID,
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

        pub fn terror(self: Self, tag: u16) !void {
            const msg = Message{
                .tag = tag,
                .command = .terror,
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

        pub fn rflush(self: Self, tag: u16) !void {
            const msg = Message{
                .tag = tag,
                .command = .rflush,
            };
            try msg.dump(self.writer);
        }

        pub fn twalk(self: Self, tag: u16, fid: u32, newfid: u32, wname: []const []const u8) !void {
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

        pub fn rclunk(self: Self, tag: u16) !void {
            const msg = Message{
                .tag = tag,
                .command = .rclunk,
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

        pub fn rremove(self: Self, tag: u16) !void {
            const msg = Message{
                .tag = tag,
                .command = .rremove,
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

        pub fn rwstat(self: Self, tag: u16) !void {
            const msg = Message{
                .tag = tag,
                .command = .rwstat,
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

            if (comm == .rerror) {
                std.log.debug("rerror: {s}", .{ comm.rerror.ename });
                return error.Rerror;
            }

            if (counting.bytes_read > size) {
                return error.MessageTooLarge;
            } else if (counting.bytes_read < size) {
                var poop_buffer: [300]u8 = undefined;
                const remainder = size - counting.bytes_read;
                const n = try self.reader.readAll(poop_buffer[0..remainder]);
                std.log.debug("Trailing poop ({d}): {any}", .{ remainder, poop_buffer[0..n] });
                // return error.MessageTooSmall;
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
    const buffer = try allocator.alloc(u8, size);
    const n = try reader.readAll(buffer);
    if (n != size) {
        return error.IncorrectStringSize;
    }
    return buffer;
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

    pub fn format(self: Message, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        switch (self.command) {
            inline else => |comm| try writer.print("Message{{ tag: {d}, command: {} }}", .{ self.tag, comm}),
        }
    }

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
            wname: []const []const u8,

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
    world_exec: bool = false,
    /// mode bit for write permission
    world_write: bool = false,
    /// mode bit for read permission
    world_read: bool = false,
    /// mode bit for execute permission
    group_exec: bool = false,
    /// mode bit for write permission
    group_write: bool = false,
    /// mode bit for read permission
    group_read: bool = false,
    /// mode bit for execute permission
    user_exec: bool = false,
    /// mode bit for write permission
    user_write: bool = false,
    /// mode bit for read permission
    user_read: bool = false,

    _padding1: u7 = 0,
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

    pub fn format(self: DirMode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}", .{
            if (self.tmp) "t" else "",
            if (self.excl) "e" else "",
            if (self.mount) "m" else "",
            if (self.auth) "a" else "",
            if (self.dir) "d" else "-",
            if (self.world_read) "r" else "-",
            if (self.world_write) "w" else "-",
            if (self.world_exec) "x" else "-",
            if (self.group_read) "r" else "-",
            if (self.group_write) "w" else "-",
            if (self.group_exec) "x" else "-",
            if (self.user_read) "r" else "-",
            if (self.user_write) "w" else "-",
            if (self.user_exec) "x" else "-",
        });
    }

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
    try testing.expectEqual(@enumToInt(DirMode.Values.exec), @bitCast(u32, DirMode{ .world_exec = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.write), @bitCast(u32, DirMode{ .world_write = true }));
    try testing.expectEqual(@enumToInt(DirMode.Values.read), @bitCast(u32, DirMode{ .world_read = true }));

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

pub const Stat = struct {
    allocator: mem.Allocator,
    pkt_size: u16,
    stype: u16,
    dev: u32,
    qid: Qid,
    mode: DirMode,
    atime: u32,
    mtime: u32,
    length: u64,
    name: []const u8,
    uid: []const u8,
    gid: []const u8,
    muid: []const u8,

    pub fn format(self: Stat, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Stat{{ type: {d}, dev: {d}, qid: {any}, mode: {any}, length: {d}, name: {s}, uid: {s}, gid: {s}, muid: {s} }}",
                         .{ self.stype, self.dev, self.qid, self.mode, self.length, self.name, self.uid, self.gid, self.muid });
    }

    pub fn deinit(self: Stat) void {
        self.allocator.free(self.name);
        self.allocator.free(self.uid);
        self.allocator.free(self.gid);
        self.allocator.free(self.muid);
    }

    pub fn clone(self: Stat, allocator: mem.Allocator) !Stat {
        var new_stat = self;
        new_stat.allocator = allocator;

        new_stat.name = try allocator.dupe(u8, self.name);
        errdefer allocator.free(new_stat.name);

        new_stat.uid = try allocator.dupe(u8, self.uid);
        errdefer allocator.free(new_stat.uid);

        new_stat.gid = try allocator.dupe(u8, self.gid);
        errdefer allocator.free(new_stat.gid);

        new_stat.muid = try allocator.dupe(u8, self.muid);

        return new_stat;
    }

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
        const mode = @bitCast(DirMode, try reader.readIntLittle(u32));
        const atime = try reader.readIntLittle(u32);
        const mtime = try reader.readIntLittle(u32);
        const length = try reader.readIntLittle(u64);
        const name = try parseWireString(allocator, reader);
        const uid = try parseWireString(allocator, reader);
        const gid = try parseWireString(allocator, reader);
        const muid = try parseWireString(allocator, reader);
        return .{
            .allocator = allocator,
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
        try writer.writeIntLittle(u32, @bitCast(u32, self.mode));
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

// 9pfuse
// <- Tversion tag 65535 msize 8192 version '9P2000'
// -> Rversion tag 65535 msize 8192 version '9P2000'
// <- Tattach tag 0 fid 0 afid -1 uname dante aname
// -> Rattach tag 0 qid (000000000000fd03 1675482522 d)
// <- Twalk tag 0 fid 0 newfid 1 nwname 0
// -> Rwalk tag 0 nwqid 0
// <- Topen tag 0 fid 1 mode 0
// -> Ropen tag 0 qid (000000000000fd03 1675482522 d) iounit 0
// <- Tclunk tag 0 fid 1
// -> Rclunk tag 0
// <- Twalk tag 0 fid 0 newfid 1 nwname 1 0:.Trash
// -> Rerror tag 0 ename No such file or directory
// <- Twalk tag 0 fid 0 newfid 1 nwname 1 0:.Trash-1000
// -> Rerror tag 0 ename No such file or directory
