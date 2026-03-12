const std = @import("std");
const posix = std.posix;
const lp = @import("launchpad.zig");
const midi = @import("midi.zig");

var running = std.atomic.Value(bool).init(true);

fn sigintHandler(sig: i32) callconv(.c) void {
    _ = sig;
    running.store(false, .release);
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const act = posix.Sigaction{
        .handler = .{ .handler = sigintHandler },
        .flags = 0,
        .mask = std.mem.zeroes(posix.sigset_t),
    };
    posix.sigaction(posix.SIG.INT, &act, null);

    const port_opt = try midi.MidiPort.init_with_name(alloc, "Launchpad");
    if (port_opt) |port| {
        defer port.deinit();

        var client = try lp.LaunchpadClient.open(alloc, port.full_name);
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
