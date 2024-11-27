const std = @import("std");
const cpu = @import("cpu.zig");
const pmm = @import("../../pmm.zig");
const paging = @import("../../paging.zig");

const log = std.log.scoped(.paging);

pub const PagingMap = struct {
    page_table_phys: pmm.PhysAddr,

    pub fn getPageTable(paging_map: PagingMap) *PageTable {
        return @alignCast(@ptrCast(paging.virtFromPhys(paging_map.page_table_phys)));
    }

    pub fn init() PagingMap {
        std.debug.assert(@sizeOf(PageTable) == std.mem.page_size);

        const alloc = pmm.alloc(1);
        @memset(paging.virtFromPhys(alloc)[0..std.mem.page_size], 0);

        const map: PagingMap = .{
            .page_table_phys = alloc,
        };

        mapHigherHalf(map);

        return map;
    }

    pub fn deinit(paging_map: PagingMap) void {
        // TODO: Free the memory used
        _ = paging_map;
    }
};

pub const PageTable = struct {
    entries: [512]Entry,

    pub const Entry = packed struct(u64) {
        present: bool,
        writable: bool,
        user: bool,
        write_through: bool,
        no_cache: bool,
        accessed: bool = false,
        dirty: bool = false,
        huge: bool,
        global: bool,
        rsv_a: u3 = 0,
        aligned_physaddr: u40,
        rsv_b: u11 = 0,
        no_exe: bool,

        /// Get the page table pointed by this entry. Should not be called on L1
        /// entries, which point to physical frames of memory, instead of a page
        /// table. Returns a virtual address space pointer using HHDM.
        pub inline fn address(entry: Entry) pmm.PhysAddr {
            return @enumFromInt(entry.aligned_physaddr << 12);
        }
    };
};

const Indices = struct {
    offset: u12,
    l1: u9,
    l2: u9,
    l3: u9,
    l4: u9,

    fn fromAddr(virt: [*]u8) Indices {
        return .{
            .offset = @truncate(@intFromPtr(virt)),
            .l1 = @truncate(@intFromPtr(virt) >> 12),
            .l2 = @truncate(@intFromPtr(virt) >> 21),
            .l3 = @truncate(@intFromPtr(virt) >> 30),
            .l4 = @truncate(@intFromPtr(virt) >> 39),
        };
    }

    pub fn format(indices: Indices, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("(L4={d}, L3={d}, L2={d}, L1={d}, +0x{x})", .{ indices.l4, indices.l3, indices.l2, indices.l1, indices.offset });
    }
};

pub fn mapPage(map: paging.Map, phys: pmm.PhysAddr, virt: [*]u8, options: paging.MapPageOptions) void {
    std.debug.assert(@intFromPtr(paging.virtFromPhys(phys)) % std.mem.page_size == 0);
    std.debug.assert(@intFromPtr(virt) % std.mem.page_size == 0);

    const indices = Indices.fromAddr(virt);
    log.debug("Indices: {}", .{indices});
    std.debug.assert(indices.offset == 0);

    var table = map.getPageTable();
    inline for (&.{ indices.l4, indices.l3, indices.l2 }, 0..) |idx, lvli| {
        const entry = &table.entries[idx];
        const lvl = 4 - lvli;

        if (entry.present) {
            if (entry.huge) {
                // TODO: Implement this
                @panic("Huge page tables are not supported");
            }
        } else {
            log.debug("Allocating page table for L{d} entry {d}", .{ lvl, idx });

            std.debug.assert(@sizeOf(PageTable) == std.mem.page_size);

            const alloc = pmm.alloc(1);
            @memset(paging.virtFromPhys(alloc)[0..std.mem.page_size], 0);

            entry.* = .{
                .present = true,
                .writable = true,
                .user = true,
                .write_through = true,
                .no_cache = true,
                .huge = false,
                .global = false,
                .no_exe = false,
                .aligned_physaddr = @intCast(@intFromEnum(alloc) >> 12),
            };
        }

        std.debug.assert(entry.present);

        table = @alignCast(@ptrCast(paging.virtFromPhys(entry.address())));
    }

    const must_invalidate = table.entries[indices.l1].present;

    table.entries[indices.l1] = .{
        .present = true,
        .writable = options.writable,
        .user = options.user,
        .write_through = true,
        .no_cache = true,
        .huge = false,
        .global = options.global,
        .no_exe = !options.executable,
        .aligned_physaddr = @truncate(@intFromEnum(phys) >> 12),
    };

    if (must_invalidate) {
        cpu.invlpg(virt);
    }
}

var initial_map: paging.Map = undefined;

pub fn init() void {
    initial_map = .{
        .page_table_phys = @enumFromInt(cpu.cr3.read()),
    };
}

pub fn mapHigherHalf(map: paging.Map) void {
    for (initial_map.getPageTable().entries, &map.getPageTable().entries, 0..) |initial_entry, *map_entry, i| {
        if (initial_entry.present) {
            std.debug.assert(i > 255);
            std.debug.assert(!map_entry.present);
            map_entry.* = initial_entry;
            std.debug.assert(map_entry.present);
        }
    }
}

pub fn setActive(map: paging.Map) void {
    cpu.cr3.write(@intFromEnum(map.page_table_phys));
}

pub fn getActive() paging.Map {
    return .{
        .page_table_phys = @enumFromInt(cpu.cr3.read()),
    };
}
