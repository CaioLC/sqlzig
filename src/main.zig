const std = @import("std");
const print = std.debug.print;

const MetaCommandResult = enum { EXIT, SUCCESS, UNRECOGNIZED_COMMAND };
const Statement = enum { INSERT, SELECT, UNRECOGNIZED_STATEMENT };
const stdin = std.io.getStdIn().reader();
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    print("Welcome to SQLZIG!\n", .{});
    // Allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize Table
    var table = Table {
        .num_rows = 0,
        .pages = undefined,
    };
    const page = try allocator.alloc(Page, PAGE_SIZE);
    table.pages[0] = *page;

    // Initialize buffer for user requests
    const buff = try allocator.alloc(u8, 30);

    // Program loop
    while (true) {
        _ = try stdout.print("(sqlzig) > ", .{});
        var input = try stdin.readUntilDelimiter(buff, '\n');
        input = input[0..input.len - 1]; // drop the delimiter
        // _ = try stdout.print("You entered: {s}\n", .{buff[0..input.len - 1]}); // -1 to remove \n from print

        if (input[0] == '.') {
            // _ = try stdout.print("Expected {s}, got: {s}\n", .{".exit", input});
            // _ = try stdout.print("Expected {b:0>8}, got: {b:0>8}\n", .{".exit", input[0..input.len - 1]});
            const command_res = meta_command(&input);
            switch (command_res) {
                MetaCommandResult.EXIT => break,
                MetaCommandResult.SUCCESS => try stdout.print("You entered: {s}\n", .{input}),
                MetaCommandResult.UNRECOGNIZED_COMMAND => try stdout.print("Unrecognized command: {s}\n", .{input}),
            }
        } else {
            const statement_res = statement_command(&input);
            switch (statement_res) {
                Statement.INSERT => parse_insert(&input),
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

fn parse_insert(table: *Table, input_buffer: *const []u8) !void {
    var params = std.mem.tokenizeAny(u8, input_buffer.*, " ");
    const row = TableRow {
        .id = try params.next(),
        .username = try params.next(),
        .email = try params.next(),
    };
    try table.insert(row);
}

const USER_NAME_SIZE = 32;
const EMAIL_SIZE = 255;
const PAGE_SIZE = 4096;
const MAX_PAGES = 100;
const TableRow = struct {
    id: u32,
    username: [USER_NAME_SIZE]u8,
    email: [EMAIL_SIZE]u8,
};

const Table = struct {
    num_rows: u32,
    pages: [MAX_PAGES]*Page,
    fn insert(row: TableRow) void {
        try stdout.print("Inserting: {s}\n", .{row});
    }
};

const Page = struct {};