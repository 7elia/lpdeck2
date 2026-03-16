const std = @import("std");
const posix = std.posix;
const lp = @import("launchpad.zig");
const midi = @import("midi.zig");
const ws = @import("ws.zig");
const config = @import("config.zig");

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

    const device_name = try config.getDeviceName(alloc);
    defer alloc.free(device_name);

    const port_opt = try midi.MidiPort.initWithName(alloc, device_name);

    if (port_opt) |port| {
        defer port.deinit();

        var client = try lp.LaunchpadClient.open(alloc, port.full_name);
        defer client.deinit();

        var server = try ws.Server.init(alloc, client);
        defer server.deinit();
        try server.start();

        while (running.load(.acquire)) {
            if (!client.client.poll()) {
                continue;
            }

            if (try client.read()) |data| {
                if (!data.on) {
                    continue;
                }

                const c = try config.loadConfig(alloc);
                for (c.value.actions) |action| {
                    if (action.x != data.note.x or action.y != data.note.y) {
                        continue;
                    }

                    try action.execute(server);
                }

                std.debug.print("{any}\n", .{data});
            }
        }

        return;
    }

    return error.DeviceNotFound;
}
