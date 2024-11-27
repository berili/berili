const std = @import("std");
const limine = @import("limine");
const cpu = @import("cpu.zig");
const paging = @import("paging.zig");
const gdt = @import("gdt.zig");
const idt = @import("idt.zig");
const apic = @import("apic.zig");
const scheduler = @import("../../scheduler.zig");

pub inline fn hcf() noreturn {
    while (true) {
        cpu.hlt();
    }
}

pub inline fn disableInterrupts() void {
    cpu.cli();
}

pub inline fn enableInterrupts() void {
    cpu.sti();
}

pub fn interruptsEnabled() bool {
    return cpu.Rflags.read().@"if";
}

pub const mapPage = paging.mapPage;
pub const mapHigherHalf = paging.mapHigherHalf;
pub const PagingMap = paging.PagingMap;
pub const initPaging = paging.init;
pub const setActiveMap = paging.setActive;
pub const getActiveMap = paging.getActive;

pub fn initCoreEarly() void {
    disableInterrupts();
}

pub fn initCore() void {
    gdt.init();
    idt.init();
    apic.init();
}

pub fn startAllCores(smp_req: limine.SmpRequest, callback: fn (core_id: usize) noreturn) noreturn {
    core_info[0] = .{
        .id = 0,
    };

    if (smp_req.response) |smp_res| {
        for (smp_res.cpus()) |core| {
            std.debug.assert(core.processor_id == core.lapic_id); // TODO: Is this always the case?

            core_info[core.processor_id] = .{
                .id = core.processor_id,
            };

            if (core.lapic_id != smp_res.bsp_lapic_id) {
                @atomicStore(
                    ?*const fn (*limine.SmpInfo) callconv(.C) noreturn,
                    &core.goto_address,
                    struct {
                        fn f(info: *limine.SmpInfo) callconv(.C) noreturn {
                            cpu.Msr.GS_BASE.write(@intFromPtr(&core_info[info.processor_id]));
                            callback(info.processor_id);
                        }
                    }.f,
                    .monotonic,
                );
            }
        }

        cpu.Msr.GS_BASE.write(@intFromPtr(&core_info[smp_res.bsp_lapic_id]));
        callback(smp_res.bsp_lapic_id);
    } else {
        std.log.warn("No SMP information from the bootloader", .{});
        cpu.Msr.GS_BASE.write(@intFromPtr(&core_info[0]));
        std.log.debug("GS_BASE=0x{x}", .{cpu.Msr.GS_BASE.read()});
        callback(0);
    }
}

// TODO: Remove this limitation
var core_info: [64]CoreInfo = undefined;

pub const CoreInfo = struct {
    id: usize,

    pub fn read() CoreInfo {
        return @as(*allowzero addrspace(.gs) volatile CoreInfo, @ptrFromInt(0)).*;
    }
};

pub const InterruptFrame = idt.InterruptFrame;

pub fn initThread(thread: *scheduler.Thread, start: *const fn () noreturn, stack: [*]u8) void {
    thread.* = .{
        .registers = std.mem.zeroes(InterruptFrame),
        .paging_map = PagingMap.init(),
    };
    thread.registers.es = gdt.selectors.kdata_64;
    thread.registers.ds = gdt.selectors.kdata_64;
    thread.registers.iret.ss = gdt.selectors.kdata_64;
    thread.registers.iret.cs = gdt.selectors.kcode_64;
    thread.registers.iret.rip = @intFromPtr(start);
    thread.registers.iret.rsp = std.mem.alignBackward(usize, @intFromPtr(stack), 16);
    thread.registers.iret.rflags = std.mem.zeroInit(cpu.Rflags, .{});
    thread.registers.iret.rflags.@"if" = true;
}

pub fn timer(handler: *const fn (frame: *InterruptFrame) void, ticks: u32) void {
    std.debug.assert(idt.timer_irq == null);
    idt.timer_irq = handler;
    apic.lapic.timer(32, ticks);
}
