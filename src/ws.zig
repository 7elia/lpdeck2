const std = @import("std");
const ws = @import("websocket");
const lp = @import("launchpad.zig");
const config = @import("config.zig");

pub const Server = struct {
    alloc: std.mem.Allocator,
    server: *ws.Server(Handler),
    app: App,

    pub fn init(alloc: std.mem.Allocator, device: lp.LaunchpadClient) !Server {
        const server = try alloc.create(ws.Server(Handler));
        server.* = try ws.Server(Handler).init(alloc, .{
            .port = 7543,
            .address = "127.0.0.1",
            .handshake = .{
                .timeout = 3,
                .max_size = 1024,
                .max_headers = 0,
            },
        });

        const app: App = .{
            .alloc = alloc,
            .targets = .empty,
            .device = device,
        };

        return .{
            .alloc = alloc,
            .server = server,
            .app = app,
        };
    }

    pub fn start(self: *Server) !void {
        _ = try self.server.listenInNewThread(&self.app);
    }

    pub fn deinit(self: *Server) void {
        self.server.stop();
        self.server.deinit();
        self.alloc.destroy(self.server);
    }
};

const Handler = struct {
    app: *App,
    conn: *ws.Conn,
    target: []const u8,

    pub fn init(h: *ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        var paths = std.mem.splitAny(u8, h.url, "/");

        if (paths.peek()) |path| {
            if (std.mem.eql(u8, path, "")) {
                _ = paths.next();
            }
        }

        if (paths.next()) |path| {
            const handler: Handler = .{
                .app = app,
                .conn = conn,
                .target = path,
            };

            try app.targets.put(app.alloc, path, handler);
            std.debug.print("Registered target {s}\n", .{path});

            const c = try config.loadConfig(app.alloc);
            for (c.value.actions) |action| {
                if (action.target) |target| {
                    if (!std.mem.eql(u8, target.id, path)) {
                        continue;
                    }

                    try action.tryWriteColor(app.device);
                }
            }

            return handler;
        }

        return error.NoTarget;
    }

    pub fn close(self: *Handler) void {
        if (self.app.targets.remove(self.target)) {
            std.debug.print("Removed target {s}\n", .{self.target});
        }

        const c = config.loadConfig(self.app.alloc) catch return;
        for (c.value.actions) |action| {
            if (action.target) |target| {
                if (!std.mem.eql(u8, target.id, self.target)) {
                    continue;
                }

                self.app.device.setColor(
                    .{ .x = action.x, .y = action.y },
                    .{ .red = 0, .green = 0 },
                    .none,
                ) catch continue;
            }
        }
    }

    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        const msg: std.json.Parsed(std.json.Value) = try std.json.parseFromSlice(
            std.json.Value,
            self.app.alloc,
            data,
            .{ .ignore_unknown_fields = true },
        );
        defer msg.deinit();

        const c = try config.loadConfig(self.app.alloc);
        blk: for (c.value.actions) |action| {
            const note: lp.Note = .{ .x = action.x, .y = action.y };

            if (action.target) |target| {
                if (!std.mem.eql(u8, target.id, self.target)) {
                    continue;
                }

                if (target.sync) |sync| {
                    if (msg.value.object.get(sync.key)) |color_value| {
                        switch (sync.type) {
                            .@"enum" => {
                                if (sync.colors) |colors| {
                                    for (0..colors.len) |i| {
                                        if (!std.mem.eql(u8, colors[i], color_value.string)) {
                                            continue;
                                        }

                                        const color: lp.Color = switch (i) {
                                            0 => .{ .red = 3, .green = 0 },
                                            1 => .{ .red = 3, .green = 2 },
                                            2 => .{ .red = 0, .green = 3 },
                                            else => unreachable,
                                        };

                                        try self.app.device.setColor(note, color, .none);

                                        continue :blk;
                                    }
                                }
                            },
                            .bool => {
                                const color: lp.Color = switch (color_value.bool) {
                                    true => .{ .red = 0, .green = 3 },
                                    false => .{ .red = 3, .green = 0 },
                                };

                                try self.app.device.setColor(note, color, .none);
                            },
                        }
                    } else return error.ValueNotPresent;
                }
            }
        }
    }
};

const App = struct {
    alloc: std.mem.Allocator,
    targets: std.StringHashMapUnmanaged(Handler),
    device: lp.LaunchpadClient,
};
