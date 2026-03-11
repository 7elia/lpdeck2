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

    const port_opt = try midi.MidiPort.init_with_name(init.gpa, "Launchpad");
    if (port_opt) |port| {
        defer port.deinit();

        var client = try lp.LaunchpadClient.open(init.gpa, port.full_name);
        defer client.deinit();

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
    } else {
        return error.NoDevice;
    }
}
