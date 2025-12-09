const std = @import("std");

pub const NAME = "glsl_analyzer";

pub const Arguments = struct {
    version: bool = false,
    channel: ChannelKind = .stdio,
    client_pid: ?c_int = null,
    dev_mode: ?[]const u8 = null,
    parse_file: ?[]const u8 = null,
    print_ast: bool = false,
    format_files: std.ArrayList([]const u8),
    tab_size: u32 = 4,
    allocator: std.mem.Allocator,

    pub const ChannelKind = union(enum) {
        stdio: void,
        socket: u16,
    };

    const usage =
        "Usage: " ++ NAME ++
        \\ [OPTIONS]
        \\
        \\LSP:
        \\     --clientProcessId <PID>  PID of the client process (used by LSP client).
        \\
        \\Options:
        \\ -h, --help               Print this message.
        \\     --stdio              Communicate over stdio. [default]
        \\ -p, --port <PORT>        Communicate over socket.
        \\     --dev-mode <PATH>    Enable development mode: redirects stderr to the given path.
        \\     --format <PATH>...   Format one or more files and exit.
        \\     --tab-size <N>       Number of spaces per indentation level (default: 4).
        \\     --parse-file <PATH>  Parses the given file, prints diagnostics, then exits.
        \\     --print-ast          Prints the parse tree. Only valid with --parse-file.
        \\
        \\
        ;

    fn printHelp() noreturn {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        stdout_writer.interface.writeAll(usage) catch {};
        stdout_writer.interface.flush() catch {};
        std.process.exit(1);
    }

    fn printVersion() noreturn {
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        stdout_writer.interface.writeAll(@import("build_options").version) catch {};
        stdout_writer.interface.flush() catch {};
        std.process.exit(0);
    }

    fn fail(comptime fmt: []const u8, args: anytype) noreturn {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        stderr_writer.interface.writeAll(usage) catch {};
        stderr_writer.interface.flush() catch {};
        std.log.err(fmt ++ "\n", args);
        std.process.exit(1);
    }

    const ValueParser = struct {
        args: *std.process.ArgIterator,
        option: []const u8,
        value: ?[]const u8,

        pub fn get(self: *@This(), name: []const u8) []const u8 {
            if (self.value) |value| return value;
            if (self.args.next()) |value| return value;
            fail("'{s}' expects an argument '{s}'", .{ self.option, name });
        }
    };

    pub fn deinit(self: *Arguments) void {
        self.format_files.deinit(self.allocator);
    }

    pub fn parse(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !Arguments {
        _ = args.skip();

        var parsed = Arguments{
            .format_files = .{},
            .allocator = allocator,
        };

        while (args.next()) |arg| {
            const option_end = std.mem.indexOfScalar(u8, arg, '=') orelse arg.len;
            const option = arg[0..option_end];

            var value_parser = ValueParser{
                .args = args,
                .option = option,
                .value = if (option_end == arg.len) null else arg[option_end + 1 ..],
            };

            if (isAny(option, &.{ "--help", "-h" })) {
                printHelp();
            }

            if (isAny(option, &.{ "--version", "-v" })) {
                printVersion();
            }

            if (isAny(option, &.{"--stdio"})) {
                parsed.channel = .stdio;
                continue;
            }

            if (isAny(option, &.{"--dev-mode"})) {
                const path = value_parser.get("PATH");
                parsed.dev_mode = path;
                continue;
            }

            if (isAny(option, &.{ "--port", "-p" })) {
                const value = value_parser.get("PORT");
                const port = std.fmt.parseInt(u16, value, 10) catch
                    fail("{s}: not a valid port number: {s}", .{ option, value });
                parsed.channel = .{ .socket = port };
                continue;
            }

            if (isAny(option, &.{"--clientProcessId"})) {
                const value = value_parser.get("PID");
                parsed.client_pid = std.fmt.parseInt(c_int, value, 10) catch
                    fail("{s}: not a valid PID: {s}", .{ option, value });
                continue;
            }

            if (isAny(option, &.{"--parse-file"})) {
                parsed.parse_file = value_parser.get("PATH");
                continue;
            }

            if (isAny(option, &.{"--print-ast"})) {
                parsed.print_ast = true;
                continue;
            }

            if (isAny(option, &.{"--tab-size"})) {
                const value = value_parser.get("N");
                parsed.tab_size = std.fmt.parseInt(u32, value, 10) catch
                    fail("{s}: not a valid number: {s}", .{ option, value });
                continue;
            }

            if (isAny(option, &.{"--format"})) {
                // Get the first file path
                const first_path = value_parser.get("PATH");
                try parsed.format_files.append(allocator, first_path);

                // Collect all remaining non-option arguments as file paths
                while (args.next()) |next_arg| {
                    if (next_arg.len > 0 and next_arg[0] == '-') {
                        // This is an option, not a file path
                        // We need to "put it back" by not consuming it
                        // Unfortunately ArgIterator doesn't support this,
                        // so we'll just break and let the outer loop handle it
                        fail("--format must be the last option when formatting multiple files", .{});
                    }
                    try parsed.format_files.append(allocator, next_arg);
                }
                continue;
            }

            fail("unexpected argument '{s}'", .{arg});
        }

        return parsed;
    }

    fn isAny(name: []const u8, expected: []const []const u8) bool {
        for (expected) |string| {
            if (std.mem.eql(u8, name, string)) return true;
        } else {
            return false;
        }
    }
};
