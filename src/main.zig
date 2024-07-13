const std = @import("std");
const print = std.debug.print;

const MetaCommandResult = enum { EXIT, SUCCESS, HELP, UNRECOGNIZED_COMMAND };
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

    pub fn format(
        self: TableRow,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        // Correctly calculate the last index for username and email
        const user_idx = for (self.username, 0..self.username.len) |u, i| {
            if (u == 170) break i;
        } else self.username.len;
        const email_idx = for (self.email, 0..self.email.len) |u, i| {
            if (u == 170) break i;
        } else self.email.len;

        if (user_idx != 0) {
            // Use the calculated indices to trim the arrays
            const trimmed_username = self.username[0..user_idx];
            const trimmed_email = self.email[0..email_idx];

            try writer.print(
                \\ {}    | {s}        | {s}
                \\
            , .{
                self.id,
                trimmed_username,
                trimmed_email,
            });
        }
    }

    fn last_index(buf: *[]u8) usize {
        for (buf, 0..buf.len) |u, i| {
            if (u == 170) return i;
        }
        return buf.len;
    }
};

const Table = struct {
    allocator: *const std.mem.Allocator,
    name: []const u8,
    pages: [TABLE_MAX_PAGES]?[*]u8,

    fn init(allocator: *const std.mem.Allocator, name: []const u8) !Table {
        return Table{
            .allocator = allocator,
            .name = name,
            .pages = undefined,
        };
    }

    fn insert(table: *Table, row: TableRow) !void {
        const mem_address = try table.row_slot(row.id);
        const new_page = table.pages[mem_address.page].?;
        const ser = try serialize(row);
        const slice_dest: []u8 = new_page[mem_address.offset .. mem_address.offset + ROW_SIZE];
        std.mem.copyForwards(u8, slice_dest, &ser);
    }

    fn row_slot(table: *Table, row_id: u32) !MemAddres {
        const page_num = row_id / ROWS_PER_PAGE;
        const page_ptr = table.pages[page_num];
        if (page_ptr == null) { // if points to unitialized variable
            const new_page = try table.allocator.alloc(u8, PAGE_SIZE);
            table.pages[page_num] = new_page.ptr;
            print("type info    :   {}\n", .{@TypeOf(new_page)});
            print("len addrs    :   {}\n", .{new_page.len});
            print("pointer addrs:   {*}\n", .{new_page.ptr});
        }
        const row_offset = row_id % ROWS_PER_PAGE;
        const byte_offset = row_offset * ROW_SIZE;
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
fn deserialize(bin: []u8) TableRow {
    const id: u32 = @bitCast(bin[0..4].*);
    // for (bin[0..4], 0..4) |byte, i| {
    //     const n: u32 = @bitCast(byte);
    //     id |= n << i * 8;
    // }
    var username: [USERNAME_SIZE]u8 = undefined;
    var email: [EMAIL_SIZE]u8 = undefined;
    std.mem.copyForwards(u8, &username, bin[4 .. 4 + USERNAME_SIZE]);
    std.mem.copyForwards(u8, &email, bin[4 + USERNAME_SIZE .. 4 + USERNAME_SIZE + EMAIL_SIZE]);
    return TableRow{ .id = id, .username = username, .email = email };
}

const Page = struct {};
const MemAddres = struct {
    page: u32,
    offset: u32,
};

fn nextLine(reader: anytype, buffer: []u8) ![]const u8 {
    const line = (try reader.readUntilDelimiter(buffer, '\n'));
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Initialize Table
    var table = try Table.init(&allocator, "my_table");

    // Initialize buffer for user requests
    var buff: [4096]u8 = undefined;

    // PROGRAM LOOP
    try stdout.print("Welcome to SQLZIG!\n", .{});
    while (true) {
        _ = try stdout.print("(sqlzig) > ", .{});
        var input = try nextLine(stdin, &buff);

        if (input[0] == '.') {
            const command_res = meta_command(&input);
            switch (command_res) {
                MetaCommandResult.EXIT => break,
                MetaCommandResult.HELP => try stdout.print(
                    \\ Available Commands:
                    \\   MetaCommands:
                    \\     .exit
                    \\     .help
                    \\   Statements:
                    \\     insert stmt
                    \\     select stmt
                    \\
                , .{}),
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
                Statement.SELECT => {
                    parse_select(&table, &input) catch |err| {
                        std.debug.print("An error occurred: {}\nInput: {s}\n", .{ err, input });
                    };
                },
                Statement.UNRECOGNIZED_STATEMENT => try stdout.print("Unrecognized: {s}\n", .{input}),
            }
        }
    }
}

fn meta_command(input_buffer: *[]const u8) MetaCommandResult {
    if (std.mem.eql(u8, input_buffer.*, ".exit")) return MetaCommandResult.EXIT;
    if (std.mem.eql(u8, input_buffer.*, ".help")) return MetaCommandResult.HELP;
    return MetaCommandResult.UNRECOGNIZED_COMMAND;
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
    std.mem.copyForwards(u8, username[0..], username_slice); // NOTE: dont know if backwards or forwards
    const email_slice = params.next() orelse return ParsingError.NoMoreParams;
    var email: [EMAIL_SIZE]u8 = undefined;
    std.mem.copyForwards(u8, email[0..], email_slice);
    const row = TableRow{
        .id = try stringToInt(id),
        .username = username,
        .email = email,
    };
    table.insert(row) catch |err| {
        print("Writing failed: {}", .{err});
    };
}

fn parse_select(table: *Table, input_buffer: *[]const u8) !void {
    _ = input_buffer;
    print("id    | username    | email\n", .{});
    for (table.pages) |page| {
        if (page) |p| {
            try print_rows(p);
        }
    }
}

fn print_rows(page: [*]u8) !void {
    // Assuming we want to run indefinitely for demonstration
    var i: u32 = 0; // Initialize the counter variable
    while (true) : (i += ROW_SIZE) {
        if (i + ROW_SIZE >= PAGE_SIZE) {
            break;
        }
        const row_bin = page[i .. i + ROW_SIZE];
        const row = deserialize(row_bin);
        // if (i < 3) print("{}\n", .{row});
        print("{}", .{row});
    }
}

fn stringToInt(s: []const u8) !u32 {
    return std.fmt.parseInt(u32, s, 10) catch unreachable; // Assuming the string is guaranteed to be a valid u32
}
