const std = @import("std");
const posix = std.posix;
const lp = @import("launchpad.zig");
const midi = @import("midi.zig");

var running = std.atomic.Value(bool).init(true);

fn sigintHandler(sig: posix.SIG) callconv(.c) void {
    _ = sig;
    running.store(false, .release);
}

pub fn main(init: std.process.Init) !void {
    const act = posix.Sigaction{
        .handler = .{ .handler = sigintHandler },
        .flags = 0,
        .mask = posix.sigemptyset(),
    };
    posix.sigaction(posix.SIG.INT, &act, null);

    midi.list_rawmidi_ports();

    var client = try lp.LaunchpadClient.open(init.gpa, "hw:4,0,0");
    defer client.close();

    try client.set_color(
        .{ .x = 0, .y = 0 },
        .{ .red = 3, .green = 0 },
        .none,
    );

    while (running.load(.acquire)) {
        if (!client.client.poll()) {
            continue;
        }

        if (try client.read()) |data| {
            std.debug.print("{any}\n", .{data});
        }
    }
}
