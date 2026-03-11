const std = @import("std");
const c = @cImport(@cInclude("alsa/asoundlib.h"));

pub const MidiClient = struct {
    in: ?*c.snd_rawmidi_t,
    out: ?*c.snd_rawmidi_t,
    descriptors: [1]c.struct_pollfd,

    pub fn open(name: []const u8) !MidiClient {
        var in: ?*c.snd_rawmidi_t = null;
        var out: ?*c.snd_rawmidi_t = null;

        const err = c.snd_rawmidi_open(
            @ptrCast(&in),
            @ptrCast(&out),
            @ptrCast(name),
            c.SND_RAWMIDI_NONBLOCK,
        );

        if (err < 0) {
            std.debug.print("Opening device failed: {s}\n", .{c.snd_strerror(err)});
            return error.MidiOpenFailed;
        }

        var pfds: [1]c.struct_pollfd = undefined;

        const count = c.snd_rawmidi_poll_descriptors(in, &pfds, pfds.len);
        if (count < 0) {
            std.debug.print("Descriptors error: {d}\n", .{count});
            return error.MidiDescriptorsFailed;
        }

        if (count != pfds.len) {
            std.debug.print("Invalid amount of data: {d}\n", .{count});
            return error.MidiDescriptorsFailed;
        }

        return .{
            .in = in,
            .out = out,
            .descriptors = pfds,
        };
    }

    pub fn close(self: *MidiClient) void {
        _ = c.snd_rawmidi_close(self.in);
        _ = c.snd_rawmidi_close(self.out);
        self.in = null;
        self.out = null;
    }

    pub fn can_read(self: MidiClient) bool {
        return self.in != null;
    }

    pub fn can_write(self: MidiClient) bool {
        return self.out != null;
    }

    pub const Data = struct {
        status: Status,
        note: u8,
        velocity: u8,

        pub const Status = enum(u8) {
            unknown = 0,
            on = 0x90,
            off = 0x80,
            cc = 0xB0,
        };
    };

    pub fn read(self: MidiClient) !?Data {
        if (!self.can_read()) {
            return error.ReadNotAvailable;
        }

        var buf: [3]u8 = undefined;

        const size = c.snd_rawmidi_read(self.in, &buf, buf.len);
        if (size < 0) {
            if (size == -@as(isize, @intCast(@intFromEnum(std.posix.E.AGAIN)))) {
                return null;
            }

            std.debug.print("Read error: {s}\n", .{c.snd_strerror(@intCast(size))});
            return error.MidiReadFailed;
        }

        if (size != buf.len) {
            std.debug.print("Read asymmetrical data: {d}\n", .{size});
            return error.MidiReadFailed;
        }

        return .{
            .status = @enumFromInt(buf[0] & 0xF0),
            .note = buf[1],
            .velocity = buf[2],
        };
    }

    pub fn write(self: MidiClient, data: Data) !void {
        if (!self.can_write()) {
            return error.WriteNotAvailable;
        }

        var msg = [_]u8{
            @intFromEnum(data.status),
            data.note,
            data.velocity,
        };

        const size = c.snd_rawmidi_write(self.out, &msg, msg.len);
        if (size < 0) {
            std.debug.print("Write error: {s}\n", .{c.snd_strerror(@intCast(size))});
            return error.MidiWriteFailed;
        }

        if (size != msg.len) {
            std.debug.print("Wrote asymmetrical data: {d}\n", .{size});
            return error.MidiWriteFailed;
        }
    }

    pub fn poll(self: *MidiClient) bool {
        _ = c.poll(&self.descriptors, 1, 50);
        return self.descriptors[0].revents & c.POLLIN != 0;
    }
};

pub const MidiPort = struct {
    name: []const u8,
    card: u16,
    device: u16,
    sub: u16,
    has_input: bool,
    has_output: bool,

    pub fn list_all(alloc: std.mem.Allocator) !std.ArrayList(MidiPort) {
        var ports: std.ArrayList(MidiPort) = .empty;

        var info: ?*c.snd_rawmidi_info_t = undefined;
        _ = c.snd_rawmidi_info_malloc(&info);
        defer c.snd_rawmidi_info_free(info);

        var card: c_int = -1;
        while (c.snd_card_next(&card) == 0 and card >= 0) {
            const card_name: []const u8 = try std.fmt.allocPrint(alloc, "hw:{d}", .{card});
        }
    }
};

pub fn list_rawmidi_ports() void {
    var info: ?*c.snd_rawmidi_info_t = undefined;
    _ = c.snd_rawmidi_info_malloc(&info);
    defer c.snd_rawmidi_info_free(info);

    std.debug.print("{s:<4} {s:<12} {s}\n", .{ "IO", "Device", "Name" });

    var card: c_int = -1;
    while (c.snd_card_next(&card) == 0 and card >= 0) {
        var card_name: [32]u8 = undefined;
        const card_name_slice = std.fmt.bufPrintZ(&card_name, "hw:{d}", .{card}) catch continue;

        var ctl: ?*c.snd_ctl_t = undefined;
        if (c.snd_ctl_open(&ctl, card_name_slice.ptr, 0) < 0) continue;
        defer _ = c.snd_ctl_close(ctl);

        var device: c_int = -1;
        while (c.snd_ctl_rawmidi_next_device(ctl, &device) == 0 and device >= 0) {
            c.snd_rawmidi_info_set_device(info, @intCast(device));

            c.snd_rawmidi_info_set_stream(info, c.SND_RAWMIDI_STREAM_INPUT);
            c.snd_rawmidi_info_set_subdevice(info, 0);
            const has_input = c.snd_ctl_rawmidi_info(ctl, info) == 0;

            c.snd_rawmidi_info_set_stream(info, c.SND_RAWMIDI_STREAM_OUTPUT);
            c.snd_rawmidi_info_set_subdevice(info, 0);
            const has_output = c.snd_ctl_rawmidi_info(ctl, info) == 0;

            const name = c.snd_rawmidi_info_get_name(info);
            const subs: c_int = @intCast(c.snd_rawmidi_info_get_subdevices_count(info));

            var sub: c_int = 0;
            while (sub < subs) : (sub += 1) {
                var hw: [32]u8 = undefined;
                const hw_slice = std.fmt.bufPrint(&hw, "hw:{d},{d},{d}", .{ card, device, sub }) catch continue;

                const io: []const u8 = if (has_input and has_output) "IO" else if (has_input) "I " else " O";

                std.debug.print("{s:<4} {s:<12} {s}\n", .{ io, hw_slice, name });
            }
        }
    }
}
