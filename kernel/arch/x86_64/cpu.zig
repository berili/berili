const gdt = @import("gdt.zig");
const idt = @import("idt.zig");

pub inline fn hlt() void {
    asm volatile ("hlt");
}

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn sti() void {
    asm volatile ("sti");
}

pub inline fn invlpg(addr: [*]u8) void {
    asm volatile ("invlpg (%[addr])"
        :
        : [addr] "r" (addr),
        : "memory"
    );
}

pub const cr2 = struct {
    pub inline fn write(value: usize) void {
        asm volatile ("mov %[value], %cr2"
            :
            : [value] "r" (value),
            : "memory"
        );
    }

    pub inline fn read() usize {
        return asm volatile ("mov %cr2, %[res]"
            : [res] "=r" (-> usize),
        );
    }
};

pub const cr3 = struct {
    pub inline fn write(value: usize) void {
        asm volatile ("mov %[value], %cr3"
            :
            : [value] "r" (value),
            : "memory"
        );
    }

    pub inline fn read() usize {
        return asm volatile ("mov %cr3, %[res]"
            : [res] "=r" (-> usize),
        );
    }
};

pub const Rflags = packed struct(u64) {
    cf: bool,
    rsv_a: u1 = 1,
    pf: bool,
    rsv_b: u1 = 0,
    af: bool,
    rsv_c: u1 = 0,
    zf: bool,
    sf: bool,
    tf: bool,
    @"if": bool,
    df: bool,
    of: bool,
    iopl: u2 = 0b11,
    nt: u1 = 1,
    md: u1 = 0,
    rf: bool,
    vm: bool,
    ac: bool,
    vif: bool,
    vip: bool,
    id: bool,
    rsv_d: u8 = 0,
    aes: bool,
    ai: bool,
    rsv_e: u32 = 0,

    pub inline fn read() Rflags {
        return asm volatile (
            \\pushfq
            \\pop %[res]
            : [res] "=r" (-> Rflags),
        );
    }
};

pub fn lgdt(gdtd: *volatile gdt.Gdtd) void {
    asm volatile ("lgdt (%rax)"
        :
        : [gdtd] "{rax}" (gdtd),
        : "memory"
    );
}

pub fn lidt(idtd: *volatile idt.Idtd) void {
    asm volatile ("lidt (%rax)"
        :
        : [idtd] "{rax}" (idtd),
        : "memory"
    );
}

pub const Msr = enum(u32) {
    APIC_BASE = 0x0000_001B,
    GS_BASE = 0xC000_0101,
    KERNEL_GS_BASE = 0xC000_0102,

    pub inline fn write(msr: Msr, value: usize) void {
        const value_low: u32 = @truncate(value);
        const value_high: u32 = @truncate(value >> 32);

        asm volatile ("wrmsr"
            :
            : [msr] "{ecx}" (@intFromEnum(msr)),
              [value_low] "{eax}" (value_low),
              [value_high] "{edx}" (value_high),
        );
    }

    pub inline fn read(msr: Msr) usize {
        var value_low: u32 = undefined;
        var value_high: u32 = undefined;

        asm volatile ("rdmsr"
            : [value_low] "={eax}" (value_low),
              [value_high] "={edx}" (value_high),
            : [msr] "{ecx}" (@intFromEnum(msr)),
        );

        return (@as(usize, value_high) << 32) | value_low;
    }
};
