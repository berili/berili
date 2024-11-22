const std = @import("std");
const cpu = @import("cpu.zig");
const pmm = @import("../../pmm.zig");
const paging = @import("../../paging.zig");

const log = std.log.scoped(.apic);

const base_physaddr: pmm.PhysAddr = @enumFromInt(0xFEE00000);

pub const lapic = struct {
    pub const Register = enum(u16) {
        id = 0x0020,
        version = 0x0030,
        tpr = 0x0080,
        apr = 0x0090,
        ppr = 0x00A0,
        eoi = 0x00B0,
        rrd = 0x00C0,
        logical_destination = 0x00D0,
        destination_format = 0x00E0,
        svr = 0x00F0,
        isr = 0x0100,
        tmr = 0x0180,
        irr = 0x0200,
        error_status = 0x0280,
        lvt_cmci = 0x02F0,
        icr = 0x0300,
        lvt_timer = 0x0320,
        lvt_thermal_sensor = 0x0330,
        lvt_performance_monitoring_counters = 0x0340,
        lvt_lint0 = 0x0350,
        lvt_lint1 = 0x0360,
        lvt_error = 0x0370,
        initial_count = 0x0380,
        current_count = 0x0390,
        divide_configuration = 0x03E0,

        pub const Mode = enum {
            read,
            write,
            read_write,

            pub fn canWrite(m: Mode) bool {
                return switch (m) {
                    .write, .read_write => true,
                    .read => false,
                };
            }

            pub fn canRead(m: Mode) bool {
                return switch (m) {
                    .read, .read_write => true,
                    .write => false,
                };
            }
        };

        pub fn mode(register: Register) Mode {
            return switch (register) {
                .id => .read_write,
                .version => .read,
                .tpr => .read_write,
                .apr => .read,
                .ppr => .read,
                .eoi => .write,
                .rrd => .read,
                .logical_destination => .read_write,
                .destination_format => .read_write,
                .svr => .read_write,
                .isr => .read,
                .tmr => .read,
                .irr => .read,
                .error_status => .read,
                .lvt_cmci => .read_write,
                .icr => .read_write,
                .lvt_timer => .read_write,
                .lvt_thermal_sensor => .read_write,
                .lvt_performance_monitoring_counters => .read_write,
                .lvt_lint0 => .read_write,
                .lvt_lint1 => .read_write,
                .lvt_error => .read_write,
                .initial_count => .read_write,
                .current_count => .read,
                .divide_configuration => .read_write,
            };
        }

        pub fn Value(register: Register) type {
            // TODO: Return packed structs for "flag-like" registers
            return switch (register) {
                .isr, .tmr, .irr => u256,
                else => u32,
            };
        }
    };

    pub fn write(comptime register: Register, value: register.Value()) void {
        std.debug.assert(register.mode().canWrite());

        switch (register.Value()) {
            u32 => @as(*volatile u32, @alignCast(@ptrCast(paging.virtFromPhys(base_physaddr) + @intFromEnum(register)))).* = value,
            else => unreachable,
        }
    }

    pub fn read(comptime register: Register) register.Value() {
        std.debug.assert(register.mode().canRead());

        return switch (register.Value()) {
            u32 => @as(*volatile u32, @alignCast(@ptrCast(paging.virtFromPhys(base_physaddr) + @intFromEnum(register)))).*,
            else => unreachable,
        };
    }

    pub fn eoi() void {
        write(.eoi, 0);
    }
};

// TODO: Rename to initLapic?
pub fn init() void {
    // We haven't updated APIC_BASE, so it should be the default
    std.debug.assert(cpu.Msr.APIC_BASE.read() & 0xFFFFF000 == @intFromEnum(base_physaddr));
    std.debug.assert(cpu.Msr.APIC_BASE.read() & 0x00000800 != 0);

    // Software-enable the local APIC and map the spurious interrupt to 0xFF
    lapic.write(.svr, 0x100 | 0xFF);
}
