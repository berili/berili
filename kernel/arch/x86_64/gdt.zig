const std = @import("std");
const cpu = @import("cpu.zig");

const log = std.log.scoped(.gdt);

pub const Entry = packed struct(u64) {
    limit_a: u16,
    base_a: u24,
    access: Access,
    limit_b: u4,
    flags: Flags,
    base_b: u8,

    pub const Access = packed struct(u8) {
        accessed: bool = false,
        read_write: bool,
        direction_conforming: bool,
        executable: bool,
        type: Type,
        dpl: u2,
        present: bool,

        pub const Type = enum(u1) {
            system = 0,
            normal = 1,
        };
    };

    pub const Flags = packed struct(u4) {
        rsv_a: u1 = 0,
        long_code: bool,
        size: bool,
        granularity: bool,
    };
};

pub const Gdtd = packed struct(u80) {
    size: u16,
    offset: [*]Entry,
};

// TODO: Avoid hardcoding this
pub const selectors = .{
    .kcode_16 = 0x08,
    .kdata_16 = 0x10,
    .kcode_32 = 0x18,
    .kdata_32 = 0x20,
    .kcode_64 = 0x28,
    .kdata_64 = 0x30,
    .udata_64 = 0x38 | 0x03,
    .ucode_64 = 0x40 | 0x03,
    .tss = 0x48,
};

var gdt = [_]Entry{
    @bitCast(@as(u64, 0)),
    .{
        .limit_a = 65535,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = true,
            .type = .normal,
            .dpl = 0,
            .present = true,
        },
        .limit_b = 0,
        .flags = .{
            .long_code = false,
            .size = false,
            .granularity = false,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 65535,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = false,
            .type = .normal,
            .dpl = 0,
            .present = true,
        },
        .limit_b = 0,
        .flags = .{
            .long_code = false,
            .size = false,
            .granularity = false,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 65535,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = true,
            .type = .normal,
            .dpl = 0,
            .present = true,
        },
        .limit_b = 15,
        .flags = .{
            .long_code = false,
            .size = true,
            .granularity = true,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 65535,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = false,
            .type = .normal,
            .dpl = 0,
            .present = true,
        },
        .limit_b = 15,
        .flags = .{
            .long_code = false,
            .size = true,
            .granularity = true,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 0,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = true,
            .type = .normal,
            .dpl = 0,
            .present = true,
        },
        .limit_b = 0,
        .flags = .{
            .long_code = true,
            .size = false,
            .granularity = false,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 0,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = false,
            .type = .normal,
            .dpl = 0,
            .present = true,
        },
        .limit_b = 0,
        .flags = .{
            .long_code = false,
            .size = false,
            .granularity = false,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 0,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = false,
            .type = .normal,
            .dpl = 3,
            .present = true,
        },
        .limit_b = 0,
        .flags = .{
            .long_code = false,
            .size = false,
            .granularity = false,
        },
        .base_b = 0,
    },
    .{
        .limit_a = 0,
        .base_a = 0,
        .access = .{
            .read_write = true,
            .direction_conforming = false,
            .executable = true,
            .type = .normal,
            .dpl = 3,
            .present = true,
        },
        .limit_b = 0,
        .flags = .{
            .long_code = true,
            .size = false,
            .granularity = false,
        },
        .base_b = 0,
    },
};

var gdtd: Gdtd = undefined;

pub fn init() void {
    gdtd = .{
        .size = @sizeOf(@TypeOf(gdt)) - 1,
        .offset = &gdt,
    };
    log.debug("GDTD=0x{x} (size=0x{x})", .{ @intFromPtr(gdtd.offset), gdtd.size });
    cpu.lgdt(&gdtd);

    log.debug("Reloading segments...", .{});
    const gs_base = cpu.Msr.GS_BASE.read(); // TODO: Do this for FS and kernel GS
    asm volatile (
        \\push %[kcode]
        \\lea 1f(%rip), %rax
        \\push %rax
        \\lretq
        \\1:
        \\mov %[kdata], %eax
        \\mov %eax, %ds
        \\mov %eax, %es
        \\mov %eax, %fs
        \\mov %eax, %gs
        \\mov %eax, %ss
        :
        : [kcode] "i" (selectors.kcode_64),
          [kdata] "i" (selectors.kdata_64),
        : "rax", "rcx", "memory"
    );
    cpu.Msr.GS_BASE.write(gs_base);

    log.debug("GDT loaded", .{});
}
