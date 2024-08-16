const std = @import("std");
// Uncomment this block to pass the first stage
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try stdout.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const connection = try listener.accept();
    defer connection.stream.close();
    try stdout.print("client connected!", .{});

    try handleHttpRequest(connection.stream);
}

pub fn handleHttpRequest(stream: net.Stream) !void {
    var buf: [1024]u8 = undefined;
    const bytes_read = try stream.read(&buf);
    const request = buf[0..bytes_read];

    if (std.mem.eql(u8, request, "GET")) {
        const response = "HTTP/1.1 200 OK\r\n\r\n";
        try stream.writeAll(response);
    }
}
