const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    print("Welcome to SQLZIG!\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const allocator = arena.allocator();
    const buff = try allocator.alloc(u8, 30);
    const exit = ".exit";
    while (true) {
        _ = try stdout.print("(sqlzig) > ", .{});
        const input = try stdin.readUntilDelimiter(buff, '\n');
        _ = try stdout.print("You entered: {s}\n", .{buff[0..input.len - 1]}); // -1 to remove \n from print
        
        if (std.mem.eql(u8, input[0..input.len-1], exit)) break 
        else {
            _ = try stdout.print("Unrecognized command: {s}\n", .{input});
            // _ = try stdout.print("Expected {s}, got: {s}\n", .{exit, input});
            // _ = try stdout.print("Expected {b:0>8}, got: {b:0>8}\n", .{exit, input});
        }
    }
}


