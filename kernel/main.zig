const std = @import("std");
const builtin = @import("builtin");
const limine = @import("limine");
const debug = @import("debug.zig");
const pmm = @import("pmm.zig");
const paging = @import("paging.zig");
const scheduler = @import("scheduler.zig");

pub const hal = switch (builtin.cpu.arch) {
    .x86_64 => @import("arch/x86_64/hal.zig"),
    else => unreachable,
};

pub const std_options = .{
    .logFn = debug.logFn,
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

const limine_requests = struct {
    export var base_revision: limine.BaseRevision = .{ .revision = 2 };
    export var memory_map: limine.MemoryMapRequest = .{};
    export var hhdm: limine.HhdmRequest = .{};
    export var smp: limine.SmpRequest = .{};
};

export fn _start() callconv(.C) noreturn {
    // TODO: Check base revision

    hal.startAllCores(limine_requests.smp, coreStart);
}

pub const panic = debug.panic;

var mem_init_done: std.atomic.Value(bool) = .{ .raw = false };

fn coreStart(core_id: usize) noreturn {
    hal.initCoreEarly();
    std.log.debug("Core #{d} started", .{hal.CoreInfo.read().id});

    if (core_id == 0) {
        pmm.init(limine_requests.memory_map);
        paging.init(limine_requests.hhdm);
        mem_init_done.store(true, .monotonic);
    }

    while (!mem_init_done.load(.monotonic)) {
        std.atomic.spinLoopHint();
    }

    hal.initCore();

    hal.enableInterrupts();

    scheduler.start();
}
