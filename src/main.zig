const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try stdout.print("Logs from your program will appear here!\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const connection = try listener.accept();
    defer connection.stream.close();
    try stdout.print("client connected!\n", .{});

    var buf: [1024]u8 = undefined;
    const bytes_read = try connection.stream.read(&buf);
    const request = buf[0..bytes_read];
    const request_target = parseRequestTarget(request);
    const request_path_value = parseRequestPath(request);
    const request_header_value = parseRequestHeader(request);

    if (std.mem.eql(u8, request_target, "/")) {
        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else if (std.mem.indexOf(u8, request, "/echo") != null) {
        const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ request_path_value.len, request_path_value });
        defer allocator.free(response);
        try connection.stream.writeAll(response);
    } else if (std.mem.indexOf(u8, request, "/user-agent") != null) {
        const response = try std.fmt.allocPrint(allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ request_header_value.len, request_header_value });
        defer allocator.free(response);
        try connection.stream.writeAll(response);
    } else {
        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }

    // std.debug.print("request path value: {s}\n", .{request_path_value});
    std.debug.print("{s}\n", .{request});
    std.debug.print("header value: {s}\n", .{request_header_value});
    // std.debug.print("request target: {s}\n", .{request_target});
}

pub fn parseRequestTarget(request: []const u8) []const u8 {
    var lines = std.mem.split(u8, request, "\r\n");
    const first_line = lines.first();
    var parts = std.mem.split(u8, first_line, " ");

    _ = parts.next();
    const target = parts.next().?;

    return target;
}

pub fn parseRequestPath(request: []const u8) []const u8 {
    const target = parseRequestTarget(request);
    const path = if (target[0] == '/') target[1..] else target;

    var path_parts = std.mem.split(u8, path, "/");
    _ = path_parts.next();
    const path_value = path_parts.next() orelse "";

    return path_value;
}

pub fn parseRequestHeader(request: []const u8) []const u8 {
    var lines = std.mem.split(u8, request, "\r\n");

    while (lines.next()) |line| {
        var lower_case_buf: [256]u8 = undefined;
        const lower_case_line = std.ascii.lowerString(&lower_case_buf, line);

        if (std.mem.startsWith(u8, lower_case_line, "user-agent")) {
            return std.mem.trim(u8, line["user-agent:".len..], " ");
        }
    }
    return "thanks for playing.";
}
