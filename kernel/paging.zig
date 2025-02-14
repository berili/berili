const std = @import("std");
const limine = @import("limine");
const pmm = @import("pmm.zig");
const hal = @import("root").hal;

pub const Map = hal.PagingMap;

const log = std.log.scoped(.paging);

var hhdm_base: usize = undefined;

pub inline fn virtFromPhys(phys: pmm.PhysAddr) [*]u8 {
    return @ptrFromInt(hhdm_base + @intFromEnum(phys));
}

pub fn init(hhdm_req: limine.HhdmRequest) void {
    if (hhdm_req.response) |hhdm_res| {
        log.debug("HHDM base address: 0x{x}", .{hhdm_res.offset});
        std.debug.assert(hhdm_res.offset % std.mem.page_size == 0);
        hhdm_base = hhdm_res.offset;
    } else @panic("No HHDM information from the bootloader");
    hal.initPaging();
}

pub const MapPageOptions = struct {
    writable: bool,
    executable: bool,
    user: bool,
    global: bool,
};

pub fn mapPage(map: Map, phys: pmm.PhysAddr, virt: [*]u8, options: MapPageOptions) void {
    log.debug("Mapping {x} --> 0x{x}", .{ phys, @intFromPtr(virt) });
    hal.mapPage(map, phys, virt, options);
}

pub const mapHigherHalf = hal.mapHigherHalf;
pub const setActive = hal.setActiveMap;
pub const getActive = hal.getActiveMap;

/// A thin wrapper around the physical memory allocator, that uses HHDM
pub const hhdm_allocator: std.mem.Allocator = .{
    .ptr = undefined,
    .vtable = &.{
        .alloc = struct {
            fn f(_: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
                if (ptr_align > std.math.log2(std.mem.page_size)) return null;
                const page_count = std.mem.alignForward(usize, len, std.mem.page_size);
                return virtFromPhys(pmm.alloc(page_count));
            }
        }.f,
        .resize = std.mem.Allocator.noResize,
        .free = std.mem.Allocator.noFree,
    },
};
