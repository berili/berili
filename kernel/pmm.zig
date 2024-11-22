const std = @import("std");
const limine = @import("limine");

// TODO: Implement a real PMM

const log = std.log.scoped(.pmm);

pub const PhysAddr = enum(usize) { _ };

pub fn init(mmap_req: limine.MemoryMapRequest) void {
    if (mmap_req.response) |mmap_res| {
        var best_region: ?[]u8 = null;

        for (mmap_res.entries(), 0..) |entry, i| {
            log.debug("Memory map entry {}: {s} 0x{x} -- 0x{x}", .{ i, @tagName(entry.kind), entry.base, entry.base + entry.length });

            if (entry.kind == .usable) {
                if (best_region == null or best_region.?.len < entry.length) {
                    best_region = @as([*]u8, @ptrFromInt(entry.base))[0..entry.length];
                }
            }
        }

        if (best_region) |reg| {
            log.debug("Using memory region 0x{x} -- 0x{x}", .{ @intFromPtr(reg.ptr), @intFromPtr(reg.ptr) + reg.len });
            next_alloc = @enumFromInt(@intFromPtr(reg.ptr));
        } else @panic("No suitable memory section found");
    } else @panic("No memory map from the bootloader");
}

var next_alloc: PhysAddr = undefined;

pub fn alloc(count: usize) PhysAddr {
    next_alloc = @enumFromInt(std.mem.alignForward(usize, @intFromEnum(next_alloc), std.mem.page_size));
    defer next_alloc = @enumFromInt(@intFromEnum(next_alloc) + count * std.mem.page_size);
    return next_alloc;
}
