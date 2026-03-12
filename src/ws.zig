const std = @import("std");
const ws = @import("websocket");

pub fn start_server(alloc: std.mem.Allocator) !void {
    var server = try ws.Server(Handler).init(alloc, .{
        .port = 7542,
        .address = "127.0.0.1",
        .handshake = .{
            .timeout = 3,
            .max_size = 1024,
            .max_headers = 0,
        },
    });

    var app: App = .{};

    try server.listen(&app);
}

const Handler = struct {
    app: *App,
    conn: *ws.Conn,

    pub fn init(h: *ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        _ = h;

        return .{
            .app = app,
            .conn = conn,
        };
    }

    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        // try self.conn.write(data);
        _ = self;

        std.debug.print("Got data: {s}\n", .{data});
    }
};

const App = struct {};
