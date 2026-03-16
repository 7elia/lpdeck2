const lp = @import("launchpad.zig");
const ws = @import("ws.zig");

pub const Action = struct {
    x: u8,
    y: u8,
    target: ?Target = null,
    color: ?[2]u8 = null,

    pub fn writeColor(self: Action, client: lp.LaunchpadClient) !void {
        if (self.color) |color| {
            try client.setColor(
                .{ .x = self.x, .y = self.y },
                .{ .red = color[0], .green = color[1] },
                .none,
            );
            return;
        }

        return error.NoDefaultColor;
    }

    pub fn tryWriteColor(self: Action, client: lp.LaunchpadClient) !void {
        self.writeColor(client) catch |err| switch (err) {
            error.NoDefaultColor => {},
            else => return err,
        };
    }

    pub fn execute(self: Action, server: ws.Server) !void {
        try self.tryWriteColor(server.app.device);

        if (self.target) |target| {
            if (server.app.targets.get(target.id)) |server_target| {
                if (target.command) |command| {
                    try server_target.conn.writeText(command);
                }
            }
        }
    }
};

pub const Target = struct {
    id: []const u8,
    command: ?[]const u8,
    color: ?[2]u8 = null,
    sync: ?Sync = null,

    pub const Sync = struct {
        type: Type,
        key: []const u8,
        colors: ?[3][]const u8 = null,

        pub const Type = enum {
            @"enum",
            bool,
        };
    };
};
