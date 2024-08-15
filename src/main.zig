const std = @import("std");
// Uncomment this block to pass the first stage
// const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // You can use print statements as follows for debugging, they'll be visible when running tests.
    try stdout.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
    // const address = try net.Address.resolveIp("127.0.0.1", 4221);
    // var listener = try address.listen(.{
    //     .reuse_address = true,
    // });
    // defer listener.deinit();
    //
    // _ = try listener.accept();
    // try stdout.print("client connected!", .{});
}
