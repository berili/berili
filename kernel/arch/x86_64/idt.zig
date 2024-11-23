const std = @import("std");
const cpu = @import("cpu.zig");
const gdt = @import("gdt.zig");
const apic = @import("apic.zig");

const log = std.log.scoped(.idt);

pub const Idt = [256]Entry;

pub const Entry = packed struct(u128) {
    offset_low: u16,
    segment: u16,
    ist: u3,
    rsv_a: u5 = 0,
    kind: Kind,
    rsv_b: u1 = 0,
    dpl: u2,
    present: bool,
    offset_high: u48,
    rsv_c: u32 = 0,

    pub const Kind = enum(u4) {
        interrupt = 0b1110,
        trap = 0b1111,
    };

    pub fn getOffset(entry: Entry) u64 {
        return (@as(u64, entry.offset_high) << 16) | entry.offset_low;
    }

    pub fn setOffset(entry: *Entry, offset: u64) void {
        entry.offset_low = @truncate(offset);
        entry.offset_high = @intCast(offset >> 16);
    }
};

pub const Idtd = packed struct(u80) {
    limit: u16,
    base: *Idt,
};

var idt: Idt = undefined;

var idtd: Idtd = undefined;

pub const Exception = enum(u8) {
    DE = 0,
    DB = 1,
    BP = 3,
    OF = 4,
    BR = 5,
    UD = 6,
    NM = 7,
    DF = 8,
    TS = 10,
    NP = 11,
    SS = 12,
    GP = 13,
    PF = 14,
    MF = 16,
    AC = 17,
    MC = 18,
    XM = 19,
    VE = 20,
    CP = 21,

    pub fn mnemonic(exception: Exception) []const u8 {
        return switch (exception) {
            inline else => |e| "#" ++ @tagName(e),
        };
    }

    pub inline fn description(exception: Exception) []const u8 {
        return switch (exception) {
            .DE => "Divide Error",
            .DB => "Debug Exception",
            .BP => "Breakpoint",
            .OF => "Overflow",
            .BR => "BOUND Range Exceeded",
            .UD => "Invalid Opcode",
            .NM => "No Math Coprocessor",
            .DF => "Double Fault",
            .TS => "Invalid TSS",
            .NP => "Segment Not Present",
            .SS => "Stack-Segment Fault",
            .GP => "General Protection",
            .PF => "Page Fault",
            .MF => "Math Fault",
            .AC => "Alignment Check",
            .MC => "Machine Check",
            .XM => "SIMD Floating-Point Exception",
            .VE => "Virtualization Exception",
            .CP => "Control Protection Exception",
        };
    }

    pub inline fn hasErrorCode(exception: Exception) bool {
        return switch (exception) {
            .DE, .DB, .BP, .OF, .BR, .UD, .NM, .MF, .MC, .XM, .VE => false,
            .DF, .TS, .NP, .SS, .GP, .PF, .AC, .CP => true,
        };
    }
};

pub fn init() void {
    idtd = .{
        .base = &idt,
        .limit = @sizeOf(Idt) - 1,
    };

    log.debug("Setting IDT stubs...", .{});

    inline for (0..256) |i| {
        idt[i] = .{
            .segment = gdt.selectors.kcode_64,
            .ist = 0, //TODO: TSS
            .kind = switch (@as(u8, @intCast(i))) {
                0...31 => .trap,
                32...255 => .interrupt,
            },
            .dpl = 0,
            .present = true,

            // TODO: These should be `undefined`, but there is a compiler bug
            .offset_low = 0,
            .offset_high = 0,
        };
        idt[i].setOffset(@intFromPtr(&switch (i) {
            // TODO: Handle reserved exceptions better
            inline 0, 1, 3...8, 10...14, 16...21 => s: {
                const exception: Exception = comptime @enumFromInt(i);
                break :s struct {
                    fn f() callconv(.Naked) void {
                        if (comptime !exception.hasErrorCode()) {
                            // Push dummy error code
                            asm volatile ("push $0");
                        }

                        asm volatile (
                            \\push %[i]
                            \\jmp interruptCommon
                            :
                            : [i] "i" (i),
                        );
                    }
                };
            },
            else => struct {
                fn f() callconv(.Naked) void {
                    asm volatile (
                        \\push $0
                        \\push %[i]
                        \\jmp interruptCommon
                        :
                        : [i] "i" (i),
                    );
                }
            },
        }.f));
    }

    cpu.lidt(&idtd);
}

export fn interruptCommon() callconv(.Naked) noreturn {
    asm volatile (
        \\testb $0x03, 0x10(%rsp)
        \\je 1f
        \\swapgs
        \\1:
        \\
        \\push %rax
        \\push %rbx
        \\push %rcx
        \\push %rdx
        \\push %rbp
        \\push %rdi
        \\push %rsi
        \\push %r8
        \\push %r9
        \\push %r10
        \\push %r11
        \\push %r12
        \\push %r13
        \\push %r14
        \\push %r15
        \\
        \\xor %rax, %rax
        \\mov %ds, %ax
        \\push %rax
        \\mov %es, %ax
        \\push %rax
        \\
        \\mov %[kdata], %ax
        \\mov %ax, %ds
        \\mov %ax, %es
        \\
        \\mov %rsp, %rdi
        \\call interruptHandler
        \\
        \\pop %rax
        \\mov %rax, %es
        \\pop %rax
        \\mov %rax, %ds
        \\
        \\pop %r15
        \\pop %r14
        \\pop %r13
        \\pop %r12
        \\pop %r11
        \\pop %r10
        \\pop %r9
        \\pop %r8
        \\pop %rsi
        \\pop %rdi
        \\pop %rbp
        \\pop %rdx
        \\pop %rcx
        \\pop %rbx
        \\pop %rax
        \\
        \\add $8, %rsp
        \\
        \\testb $0x03, 0x10(%rsp)
        \\je 1f
        \\swapgs
        \\1:
        \\
        \\add $8, %rsp
        \\iretq
        :
        : [kcode] "i" (gdt.selectors.kcode_64),
          [kdata] "i" (gdt.selectors.kdata_64),
    );
}

const IretFrame = packed struct(u384) {
    err: u64,
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

const InterruptFrame = packed struct {
    es: u64,
    ds: u64,
    r15: u64,
    r14: u64,
    r13: u64,
    r12: u64,
    r11: u64,
    r10: u64,
    r9: u64,
    r8: u64,
    rsi: u64,
    rdi: u64,
    rbp: u64,
    rdx: u64,
    rcx: u64,
    rbx: u64,
    rax: u64,
    vector: u64,
    iret: IretFrame,
};

export fn interruptHandler(frame: *InterruptFrame) callconv(.C) void {
    switch (frame.vector) {
        inline 0, 1, 3...8, 10...14, 16...21 => |exception_i| {
            const exception: Exception = @enumFromInt(exception_i);
            log.debug("Exception {x:0>2} {s}: {s}", .{ exception_i, exception.mnemonic(), exception.description() });
            log.debug(
                \\Register dump:
                \\rax={x:0>16} rbx={x:0>16} rcx={x:0>16} rdx={x:0>16}
                \\rsi={x:0>16} rdi={x:0>16} rbp={x:0>16} rsp={x:0>16}
                \\ r8={x:0>16}  r9={x:0>16} r10={x:0>16} r11={x:0>16}
                \\r12={x:0>16} r13={x:0>16} r14={x:0>16} r15={x:0>16}
                \\rip={x:0>16} cr2={x:0>16} cr3={x:0>16} err={x:0>16}
            , .{ frame.rax, frame.rbx, frame.rcx, frame.rdx } ++
                .{ frame.rsi, frame.rdi, frame.rbp, frame.iret.rsp } ++
                .{ frame.r8, frame.r9, frame.r10, frame.r11 } ++
                .{ frame.r12, frame.r13, frame.r14, frame.r15 } ++
                .{ frame.iret.rip, cpu.cr2.read(), cpu.cr3.read(), frame.iret.err });

            cpu.cli();
            cpu.hlt();
        },
        else => {
            log.debug("Interrupt {d}", .{frame.vector});
            // TODO: Check if it's an IRQ
            apic.lapic.eoi();
        },
    }
}
