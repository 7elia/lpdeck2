const std = @import("std");
const MidiClient = @import("midi.zig").MidiClient;

pub const LaunchpadClient = struct {
    client: *MidiClient,

    pub fn open(alloc: std.mem.Allocator, name: []const u8) !LaunchpadClient {
        const client = try alloc.create(MidiClient);
        client.* = try MidiClient.open(name);

        return .{
            .client = client,
        };
    }

    pub fn close(self: LaunchpadClient) void {
        self.reset() catch std.debug.print("Couldn't reset\n", .{});
        self.client.close();
    }

    pub const Note = struct {
        x: u8,
        y: u8,

        pub const ButtonType = enum {
            pad,
            button,

            pub fn init(x: u8, y: u8) ButtonType {
                const r: ButtonType = if (x >= 8) .button else .pad;

                if (r == .pad and (x < 0 or y < 0 or x > 7 or y > 7)) {
                    return error.InvalidPadPosition;
                }

                return r;
            }
        };

        pub fn button_type(self: Note) ButtonType {
            return ButtonType.init(self.x, self.y);
        }

        pub fn read(note: u8) !Note {
            const x = note % 16;
            const y = note / 16;

            return .{
                .x = x,
                .y = y,
            };
        }

        pub fn serialize(self: Note) u8 {
            return self.x + 16 * self.y;
        }
    };

    pub const Color = struct {
        red: u8,
        green: u8,

        pub const MIN = 0;
        pub const MAX = 3;

        pub const BackBufferOperation = enum { none, clear, copy };

        pub fn init(red: u8, green: u8) Color {
            return .{
                .red = std.math.clamp(red, MIN, MAX),
                .green = std.math.clamp(green, MIN, MAX),
            };
        }

        pub fn serialize(self: Color, op: BackBufferOperation) u8 {
            const flags: u8 = switch (op) {
                .none => 0,
                .clear => 8,
                .copy => 12,
            };

            return 16 * self.green + self.red + flags;
        }

        pub fn is_off(self: Color) bool {
            return self.red == MIN and self.green == MIN;
        }
    };

    pub const Read = struct {
        on: bool,
        note: Note,
    };

    pub fn read(self: LaunchpadClient) !?Read {
        const data = try self.client.read();
        if (data == null) {
            return null;
        }

        switch (data.?.status) {
            .on, .cc => {
                const note = try Note.read(data.?.note);

                switch (data.?.velocity) {
                    0 => return .{
                        .note = note,
                        .on = false,
                    },
                    else => return .{
                        .note = note,
                        .on = true,
                    },
                }
            },
            else => |status| {
                std.debug.print("Invalid status {any}\n", .{status});
                return error.LaunchpadWrongStatus;
            },
        }
    }

    pub fn set_color(self: LaunchpadClient, note: Note, color: Color, op: Color.BackBufferOperation) !void {
        const status: MidiClient.Data.Status = if (color.is_off()) .off else .on;

        try self.client.write(.{
            .status = status,
            .note = note.serialize(),
            .velocity = color.serialize(op),
        });
    }

    pub fn reset(self: LaunchpadClient) !void {
        try self.client.write(.{
            .status = .cc,
            .note = 0,
            .velocity = 0,
        });
    }
};
