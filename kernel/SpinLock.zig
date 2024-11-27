const std = @import("std");

const SpinLock = @This();

// TODO: Store thread ID and detect deadlocks
locked: u32 = 0,

pub fn lock(spin_lock: *SpinLock) void {
    while (@cmpxchgWeak(u32, &spin_lock.locked, 0, 1, .seq_cst, .seq_cst) != null) {
        std.atomic.spinLoopHint();
    }
}

pub fn unlock(spin_lock: *SpinLock) void {
    if (@cmpxchgStrong(u32, &spin_lock.locked, 1, 0, .seq_cst, .seq_cst) != null) {
        @panic("Tried to unlock non-locked spinlock");
    }
}

pub fn forceUnlock(spin_lock: *SpinLock) void {
    if (@cmpxchgStrong(u32, &spin_lock.locked, 1, 0, .seq_cst, .seq_cst) != null) {}
}
