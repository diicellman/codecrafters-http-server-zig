const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;
const Thread = std.Thread;
const fs = std.fs;

const Request = struct {
    method: []const u8,
    path: []const u8,
    headers: Headers,
};

const Headers = struct {
    map: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Headers {
        return .{
            .map = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *Headers) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }

    fn put(self: *Headers, key: []const u8, value: []const u8) !void {
        const lower_key = try std.ascii.allocLowerString(self.allocator, key);
        errdefer self.allocator.free(lower_key);
        try self.map.put(lower_key, value);
    }

    fn get(self: Headers, key: []const u8) ?[]const u8 {
        var lower_key_buf: [256]u8 = undefined;
        const lower_key = std.ascii.lowerString(&lower_key_buf, key);
        return self.map.get(lower_key);
    }
};

const Endpoint = union(enum) {
    root,
    echo: []const u8,
    user_agent,
    file: []const u8,
    not_found,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Server starting...\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();
        try stdout.print("Client connected!\n", .{});

        const thread = try Thread.spawn(.{}, handleConnection, .{ connection, allocator });
        thread.detach();
    }
}

fn handleConnection(connection: net.Server.Connection, allocator: std.mem.Allocator) !void {
    defer connection.stream.close();

    var buf: [1024]u8 = undefined;
    const bytes_read = try connection.stream.read(&buf);
    const raw_request = buf[0..bytes_read];

    var request = try parseRequest(raw_request, allocator);
    defer request.headers.deinit();

    const endpoint = try routeRequest(request.path, allocator);
    try handleEndpoint(endpoint, connection, request, allocator);
}

fn parseRequest(raw_request: []const u8, allocator: std.mem.Allocator) !Request {
    var lines = std.mem.split(u8, raw_request, "\r\n");
    const first_line = lines.next() orelse return error.InvalidRequest;

    var parts = std.mem.split(u8, first_line, " ");
    const method = parts.next() orelse return error.InvalidRequest;
    const path = parts.next() orelse return error.InvalidRequest;

    var headers = Headers.init(allocator);
    errdefer headers.deinit();

    while (lines.next()) |line| {
        if (line.len == 0) break;
        var header_parts = std.mem.split(u8, line, ":");
        const key = std.mem.trim(u8, header_parts.next() orelse continue, " ");
        const value = std.mem.trim(u8, header_parts.next() orelse continue, " ");
        try headers.put(key, value);
    }

    return Request{
        .method = method,
        .path = path,
        .headers = headers,
    };
}

fn routeRequest(path: []const u8, allocator: std.mem.Allocator) !Endpoint {
    if (std.mem.eql(u8, path, "/")) {
        return Endpoint.root;
    } else if (std.mem.startsWith(u8, path, "/echo/")) {
        const echo_content = try allocator.dupe(u8, path[6..]);
        return Endpoint{ .echo = echo_content };
    } else if (std.mem.eql(u8, path, "/user-agent")) {
        return Endpoint.user_agent;
    } else if (std.mem.startsWith(u8, path, "/files/")) {
        const file_name = try allocator.dupe(u8, path[7..]);
        return Endpoint{ .file = file_name };
    } else {
        return Endpoint.not_found;
    }
}

fn handleEndpoint(endpoint: Endpoint, connection: net.Server.Connection, request: Request, allocator: std.mem.Allocator) !void {
    switch (endpoint) {
        .root => try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n"),
        .echo => |content| {
            const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ content.len, content });
            defer allocator.free(response);
            try connection.stream.writeAll(response);
            allocator.free(content);
        },
        .user_agent => {
            const user_agent = request.headers.get("User-Agent") orelse "";
            const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ user_agent.len, user_agent });
            defer allocator.free(response);
            try connection.stream.writeAll(response);
        },
        .file => |file_name| {
            const file_content = readFile(file_name, allocator) catch |err| {
                if (err == error.FileNotFound) {
                    try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
                } else {
                    try connection.stream.writeAll("HTTP/1.1 500 Internal Server Error\r\n\r\n");
                }
                allocator.free(file_name);
                return;
            };
            defer allocator.free(file_content);
            defer allocator.free(file_name);

            const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {d}\r\n\r\n{s}", .{ file_content.len, file_content });
            defer allocator.free(response);
            try connection.stream.writeAll(response);
        },
        .not_found => try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n"),
    }
}

fn readFile(file_name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file_path = try std.fmt.allocPrint(allocator, "/tmp/{s}", .{file_name});
    defer allocator.free(file_path);

    const file = try fs.cwd().openFile(file_path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const buffer = try allocator.alloc(u8, file_size);
    errdefer allocator.free(buffer);

    const bytes_read = try file.readAll(buffer);
    if (bytes_read != file_size) return error.IncompleteRead;

    return buffer;
}
