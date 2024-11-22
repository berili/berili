const std = @import("std");
const hal = @import("root").hal;

const SpinLock = @This();

data: std.atomic.Value(u32) = .{ .raw = 0 },
refcount: std.atomic.Value(usize) = .{ .raw = 0 },
interrupts_enabled: bool = false,

pub fn lock(spin_lock: *SpinLock) void {
    _ = spin_lock.refcount.fetchAdd(1, .monotonic);

    const interrupts_enabled = hal.interruptsEnabled();

    hal.disableInterrupts();

    while (true) {
        if (spin_lock.data.swap(1, .acquire) == 0) {
            break;
        }

        while (spin_lock.data.fetchAdd(0, .monotonic) != 0) {
            if (interrupts_enabled) hal.enableInterrupts();
            std.atomic.spinLoopHint();
            hal.disableInterrupts();
        }
    }

    _ = spin_lock.refcount.fetchSub(1, .monotonic);
    @fence(.acquire);
    spin_lock.interrupts_enabled = interrupts_enabled;
}

pub fn unlock(spin_lock: *SpinLock) void {
    spin_lock.data.store(0, .release);
    @fence(.release);
    if (spin_lock.interrupts_enabled) hal.enableInterrupts();
}
