const std = @import("std");
const builtin = @import("builtin");
const ws = @import("ws.zig");
const lp = @import("launchpad.zig");
const ac = @import("action.zig");

const DEFAULT_CONFIG =
    \\{
    \\  "device_name": "Launchpad",
    \\  "actions": []
    \\}
;

pub const Config = struct {
    device_name: []const u8,
    actions: []ac.Action = &.{},
};

fn getEnv(alloc: std.mem.Allocator, key: []const u8) !?[]u8 {
    const opt: ?[]u8 = std.process.getEnvVarOwned(alloc, key) catch null;
    if (opt) |value| {
        if (value.len > 0) {
            return value;
        }

        alloc.free(value);
    }

    return null;
}

fn resolveConfigDir(alloc: std.mem.Allocator) ![]u8 {
    return switch (builtin.os.tag) {
        .linux => blk: {
            if (try getEnv(alloc, "XDG_CONFIG_HOME")) |xdg| {
                defer alloc.free(xdg);
                break :blk try std.fmt.allocPrint(alloc, "{s}/lpdeck2", .{xdg});
            }

            if (try getEnv(alloc, "HOME")) |home| {
                defer alloc.free(home);
                break :blk try std.fmt.allocPrint(alloc, "{s}/.config/lpdeck2", .{home});
            }

            break :blk error.NoHome;
        },
        .windows => blk: {
            if (try getEnv(alloc, "LocalAppData")) |appdata| {
                defer alloc.free(appdata);
                break :blk try std.fmt.allocPrint(alloc, "{s}\\lpdeck2", .{appdata});
            }

            break :blk error.NoAppData;
        },
        .macos => blk: {
            if (try getEnv(alloc, "HOME")) |home| {
                defer alloc.free(home);
                break :blk try std.fmt.allocPrint(alloc, "{s}/Library/Application Support/lpdeck2", .{home});
            }

            break :blk error.NoHome;
        },
        else => @panic("Unknown os"),
    };
}

fn ensureDir(path: []const u8) !void {
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn ensureConfigFile(path: []const u8) !void {
    if (std.fs.openFileAbsolute(path, .{})) |f| {
        f.close();
        return;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }

    const f = try std.fs.createFileAbsolute(path, .{});
    defer f.close();

    try f.writeAll(DEFAULT_CONFIG);

    std.debug.print("Created config file\n", .{});
}

pub fn loadConfig(alloc: std.mem.Allocator) !std.json.Parsed(Config) {
    const dir_path = try resolveConfigDir(alloc);
    defer alloc.free(dir_path);

    try ensureDir(dir_path);

    const sep = if (builtin.os.tag == .windows) "\\" else "/";
    const config_path = try std.fmt.allocPrint(alloc, "{s}{s}config.json", .{ dir_path, sep });
    defer alloc.free(config_path);

    try ensureConfigFile(config_path);

    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();

    const raw = try file.readToEndAlloc(alloc, 1024 * 1024 * 5);
    defer alloc.free(raw);

    return try std.json.parseFromSlice(Config, alloc, raw, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
}

pub fn getDeviceName(alloc: std.mem.Allocator) ![]const u8 {
    const config = try loadConfig(alloc);
    defer config.deinit();

    return try alloc.dupe(u8, config.value.device_name);
}
