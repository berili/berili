const std = @import("std");
const paging = @import("paging.zig");
const SpinLock = @import("SpinLock.zig");
const hal = @import("root").hal;

const log = std.log.scoped(.scheduler);

pub const Thread = struct {
    registers: hal.InterruptFrame,
    paging_map: hal.PagingMap,
    prev: ?*Thread = null,
    next: ?*Thread = null,

    pub fn new(startFn: *const fn () noreturn) *Thread {
        const thread = paging.hhdm_allocator.create(Thread) catch @panic("Ran out of memory while allocating thread");
        const stack = paging.hhdm_allocator.alloc(u8, 64) catch @panic("Ran out of memory while allocating stack for thread"); // TODO: Make this configurable
        hal.initThread(thread, startFn, @ptrCast(&stack[stack.len - 1]));
        return thread;
    }
};

const ThreadList = struct {
    first: ?*Thread = null,
    last: ?*Thread = null,
    spinlock: SpinLock = .{},

    fn enqueue(list: *ThreadList, thread: *Thread) void {
        list.spinlock.lock();
        defer list.spinlock.unlock();

        std.debug.assert(list.first == null or list.first.?.prev == null);
        std.debug.assert(list.last == null or list.last.?.next == null);
        std.debug.assert((list.first == null and list.last == null) or (list.first != null and list.last != null));
        std.debug.assert(thread.prev == null);
        std.debug.assert(thread.next == null);

        if (list.last) |last| {
            last.next = thread;
            thread.prev = last;
            list.last = thread;
        } else {
            std.debug.assert(list.first == null);
            list.first = thread;
            list.last = thread;
        }
    }

    fn pop(list: *ThreadList) ?*Thread {
        list.spinlock.lock();
        defer list.spinlock.unlock();

        std.debug.assert(list.first == null or list.first.?.prev == null);
        std.debug.assert(list.last == null or list.last.?.next == null);
        std.debug.assert((list.first == null and list.last == null) or (list.first != null and list.last != null));

        if (list.first) |first| {
            if (first.next) |n| {
                n.prev = null;
            } else {
                list.last = null;
            }
            list.first = first.next;
            first.next = null;

            std.debug.assert(first.prev == null);
            std.debug.assert(first.next == null);
            return first;
        } else {
            return null;
        }
    }
};

var ready_threads: ThreadList = .{};

// TODO: Remove this limitation
var current_thread: [64]?*Thread = undefined;

pub fn reschedule(frame: *hal.InterruptFrame) void {
    // Save state
    current_thread[hal.CoreInfo.read().id].?.* = .{
        .registers = frame.*,
        .paging_map = paging.getActive(),
    };

    ready_threads.enqueue(current_thread[hal.CoreInfo.read().id].?);
    current_thread[hal.CoreInfo.read().id] = ready_threads.pop().?;

    // Restore state
    paging.setActive(current_thread[hal.CoreInfo.read().id].?.paging_map);
    frame.* = current_thread[hal.CoreInfo.read().id].?.registers;

    std.debug.assert(frame.iret.rflags.@"if");
}

pub fn start() noreturn {
    if (hal.CoreInfo.read().id != 0) hal.hcf();

    const init_thread = paging.hhdm_allocator.create(Thread) catch @panic("Ran out of memory while allocating thread");
    init_thread.* = .{
        .registers = undefined,
        .paging_map = undefined,
    };
    current_thread[hal.CoreInfo.read().id] = init_thread;

    hal.timer(reschedule, 100000);

    const test_thread = Thread.new(&testThreadStart);
    ready_threads.enqueue(test_thread);

    while (true) {
        log.debug("Hello", .{});
        for (0..100) |_| std.atomic.spinLoopHint();
    }
}

fn testThreadStart() noreturn {
    while (true) {
        log.debug("Bye", .{});
        for (0..100) |_| std.atomic.spinLoopHint();
    }
}
