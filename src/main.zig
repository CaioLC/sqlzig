const std = @import("std");
const print = std.debug.print;

const MetaCommandResult = enum { EXIT, SUCCESS, UNRECOGNIZED_COMMAND };
const Statement = enum { INSERT, SELECT, UNRECOGNIZED_STATEMENT };
const ParsingError = error{NoMoreParams};

const ID_SIZE = 4;
const USERNAME_SIZE = 32;
const EMAIL_SIZE = 255;
const PAGE_SIZE = 4096;
const TABLE_MAX_PAGES = 100;
const ROW_SIZE = ID_SIZE + USERNAME_SIZE + EMAIL_SIZE;
const ROWS_PER_PAGE = PAGE_SIZE / ROW_SIZE;
const TABLE_MAX_ROWS = ROWS_PER_PAGE * TABLE_MAX_PAGES;

const TableRow = struct {
    id: u32,
    username: [USERNAME_SIZE]u8,
    email: [EMAIL_SIZE]u8,
};

const Table = struct {
    allocator: *const std.mem.Allocator,
    name: []const u8,
    num_rows: u32,
    pages: [TABLE_MAX_PAGES]?*[]u8,

    fn init(allocator: *const std.mem.Allocator, name: []const u8) !Table {
        return Table{
            .allocator = allocator,
            .name = name,
            .num_rows = 0,
            .pages = undefined,
        };
    }

    fn insert(table: *Table, row: TableRow) !void {
        const mem_address = try table.row_slot(row.id);
        if (table.pages[mem_address.page]) |page_ptr| {
            print("{any}\n", .{page_ptr.*.len});
            const ser = try serialize(row);
            print("{b}", .{ser});
        } else {
            unreachable;
        }
    }

    fn row_slot(table: *Table, row_id: u32) !MemAddres {
        const page_num = row_id / ROWS_PER_PAGE;
        const page_ptr = table.pages[page_num];
        if (page_ptr == null) { // if points to unitialized variable
            print("Pointer is null or uninitialized\n", .{});
            var new_page = try table.allocator.alloc(u8, PAGE_SIZE);
            table.pages[page_num] = &new_page;
        }
        const row_offset = row_id % ROWS_PER_PAGE;
        const byte_offset = row_offset * ROW_SIZE;
        // print("page_num {}\n", .{page_num});
        // print("page {}\n", .{&table.pages[page_num]});
        // print("row_offset {}\n", .{row_offset});
        // print("byte_offset {}\n", .{byte_offset});
        return MemAddres{ .page = page_num, .offset = byte_offset };
    }
};

fn serialize(row: TableRow) ![ROW_SIZE]u8 {
    var buffer: [291]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    var writer = fbs.writer();
    try writer.writeInt(u32, row.id, std.builtin.Endian.little);
    for (row.username) |byte| {
        try writer.writeByte(byte);
    }
    for (row.email) |byte| {
        try writer.writeByte(byte);
    }
    return buffer;
}
// fn deserialize(bin: *[ROW_SIZE]u8) TableRow {
// }

const Page = struct {};
const MemAddres = struct {
    page: u32,
    offset: u32,
};

fn nextLine(reader: anytype, buffer: []u8) ![]const u8 {
    const line = (try reader.readUntilDelimiter(buffer, '\n'));
    // trim annoying windows-only carriage return character
    if (@import("builtin").os.tag == .windows) {
        return std.mem.trimRight(u8, line, "\r");
    }
    return line;
}

pub fn main() !void {
    // PROGRAM SETUP
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    // Allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Initialize Table
    var table = try Table.init(&allocator, "my_table");

    // Initialize buffer for user requests
    // var buff: [4096]u8 = undefined;
    var buff: [100]u8 = undefined;

    // PROGRAM LOOP
    try stdout.print("Welcome to SQLZIG!\n", .{});
    while (true) {
        _ = try stdout.print("(sqlzig) > ", .{});
        var input = try nextLine(stdin, &buff);
        // input = input[0..input.len - 1]; // drop the delimiter

        if (input[0] == '.') {
            // _ = try stdout.print("Expected {s}, got: {s}\n", .{".exit", input});
            // _ = try stdout.print("Expected {b:0>8}, got: {b:0>8}\n", .{".exit", input[0..input.len - 1]});
            const command_res = meta_command(&input);
            switch (command_res) {
                MetaCommandResult.EXIT => break,
                MetaCommandResult.SUCCESS => try stdout.print("You entered: {s}\n", .{&input}),
                MetaCommandResult.UNRECOGNIZED_COMMAND => try stdout.print("Unrecognized command: {s}\n", .{input}),
            }
        } else {
            const statement_res = statement_command(&input);
            switch (statement_res) {
                Statement.INSERT => {
                    parse_insert(&table, &input) catch |err| {
                        std.debug.print("An error occurred: {}\nInput: {s}\n", .{ err, input });
                    };
                },
                Statement.SELECT => try stdout.print("Selecting!\n", .{}),
                Statement.UNRECOGNIZED_STATEMENT => try stdout.print("Unrecognized: {s}\n", .{input}),
            }
        }
    }
}

fn meta_command(input_buffer: *[]const u8) MetaCommandResult {
    if (std.mem.eql(u8, input_buffer.*, ".exit")) {
        return MetaCommandResult.EXIT;
    } else {
        return MetaCommandResult.UNRECOGNIZED_COMMAND;
    }
}

fn statement_command(input_buffer: *[]const u8) Statement {
    if (input_buffer.len < 6) return Statement.UNRECOGNIZED_STATEMENT;
    if (std.mem.eql(u8, input_buffer.*[0..6], "insert")) return Statement.INSERT;
    if (std.mem.eql(u8, input_buffer.*[0..6], "select")) return Statement.SELECT;
    return Statement.UNRECOGNIZED_STATEMENT;
}

fn parse_insert(table: *Table, input_buffer: *[]const u8) !void {
    var params = std.mem.tokenizeAny(u8, input_buffer.*, " ");
    // allocate all tokens
    _ = params.next().?; // this is the "insert" statement
    const id = params.next() orelse return ParsingError.NoMoreParams;
    const username_slice = params.next() orelse return ParsingError.NoMoreParams;
    var username: [USERNAME_SIZE]u8 = undefined;
    std.mem.copyBackwards(u8, username[0..], username_slice);
    const email_slice = params.next() orelse return ParsingError.NoMoreParams;
    var email: [EMAIL_SIZE]u8 = undefined;
    std.mem.copyBackwards(u8, email[0..], email_slice);
    const row = TableRow{
        .id = try stringToInt(id),
        .username = username,
        .email = email,
    };
    try table.insert(row);
}

fn stringToInt(s: []const u8) !u32 {
    return std.fmt.parseInt(u32, s, 10) catch unreachable; // Assuming the string is guaranteed to be a valid u32
}
