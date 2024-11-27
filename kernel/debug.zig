const std = @import("std");
const hal = @import("root").hal;
const SpinLock = @import("SpinLock.zig");

var last_newline: bool = false;

pub const Writer = struct {
    prefix_len: usize,

    fn writeFn(ctx: *const anyopaque, bytes: []const u8) error{}!usize {
        const self: *const Writer = @ptrCast(@alignCast(ctx));

        for (bytes) |char| {
            if (last_newline) {
                last_newline = false;
                for (0..self.prefix_len - 2) |_| putc(' ');
                putc('|');
                putc(' ');
            }

            if (char == '\n') {
                last_newline = true;
            }

            putc(char);
        }

        return bytes.len;
    }

    pub fn any(self: *const Writer) std.io.AnyWriter {
        return .{
            .context = self,
            .writeFn = writeFn,
        };
    }
};

fn putc(char: u8) void {
    // TODO: Abstract this
    asm volatile (
        \\outb %al, $0xE9
        :
        : [char] "al" (char),
    );
}

var spin_lock = SpinLock{};

pub fn logFn(comptime level: std.log.Level, comptime scope: @Type(.EnumLiteral), comptime fmt: []const u8, args: anytype) void {
    const prefix = std.fmt.comptimePrint("[{s}] ({s}) ", .{ @tagName(level), @tagName(scope) });

    var debug_writer = Writer{ .prefix_len = prefix.len };
    const writer = debug_writer.any();

    spin_lock.lock();
    defer spin_lock.unlock();
    last_newline = false;
    std.fmt.format(writer, prefix ++ fmt ++ "\n", args) catch unreachable;
}

var panic_panic = false;
pub fn panic(msg: []const u8, _: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);
    hal.disableInterrupts();

    if (panic_panic) {
        // Nested panic! Oh no!
        for ("Panic panic: ") |c| {
            putc(c);
        }
        for (msg) |c| {
            putc(c);
        }
        putc('\n');
    } else {
        panic_panic = true;
        spin_lock.forceUnlock();
        std.log.err(
            \\PANIC: {s}
            \\Panicked at 0x{x}
        , .{ msg, ret_addr orelse @returnAddress() });
    }

    hal.hcf();
}
