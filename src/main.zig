const std = @import("std");
const print = std.debug.print;

const MetaCommandResult = enum { EXIT, SUCCESS, UNRECOGNIZED_COMMAND };
const Statement = enum { INSERT, SELECT, UNRECOGNIZED_STATEMENT };

pub fn main() !void {
    print("Welcome to SQLZIG!\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    const allocator = arena.allocator();
    const buff = try allocator.alloc(u8, 30);
    while (true) {
        _ = try stdout.print("(sqlzig) > ", .{});
        const input = try stdin.readUntilDelimiter(buff, '\n');
        // _ = try stdout.print("You entered: {s}\n", .{buff[0..input.len - 1]}); // -1 to remove \n from print

        if (input[0] == '.') {
            // _ = try stdout.print("Expected {s}, got: {s}\n", .{".exit", input});
            // _ = try stdout.print("Expected {b:0>8}, got: {b:0>8}\n", .{".exit", input[0..input.len - 1]});
            const command_res = meta_command(&input[0..input.len - 1]);
            switch (command_res) {
                MetaCommandResult.EXIT => break,
                MetaCommandResult.SUCCESS => try stdout.print("You entered: {s}\n", .{input}),
                MetaCommandResult.UNRECOGNIZED_COMMAND => try stdout.print("Unrecognized command: {s}\n", .{input}),
            }
        } else {
            const statement_res = statement_command(&input[0..input.len - 1]);
            switch (statement_res) {
                Statement.INSERT => try stdout.print("Inserting!\n", .{}),
                Statement.SELECT => try stdout.print("Selecting!\n", .{}),
                Statement.UNRECOGNIZED_STATEMENT => try stdout.print("Unrecognized: {s}\n", .{input}),
            }
        }
    }
}

fn meta_command(input_buffer: *const []u8) MetaCommandResult {
    if (std.mem.eql(u8, input_buffer.*, ".exit")) {
        return MetaCommandResult.EXIT;
    } else {
        return MetaCommandResult.UNRECOGNIZED_COMMAND;
    }
}

fn statement_command(input_buffer: *const []u8) Statement {
    if (std.mem.eql(u8, input_buffer.*[0..6], "insert")) return Statement.INSERT;
    if (std.mem.eql(u8, input_buffer.*[0..6], "select")) return Statement.SELECT;
    return Statement.UNRECOGNIZED_STATEMENT;
}

