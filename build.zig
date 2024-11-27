const std = @import("std");

const Arch = enum {
    x86_64,

    pub fn toZig(arch: Arch) std.Target.Cpu.Arch {
        return switch (arch) {
            inline else => |a| @field(std.Target.Cpu.Arch, @tagName(a)),
        };
    }
};

pub fn build(b: *std.Build) !void {
    b.top_level_steps.clearRetainingCapacity();

    const optimize = b.standardOptimizeOption(.{});

    const arch = b.option(Arch, "arch", "The architecture to compile for") orelse .x86_64;

    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = arch.toZig(),
        .abi = .none,
        .os_tag = .freestanding,
        .cpu_features_add = switch (arch) {
            .x86_64 => std.Target.x86.featureSet(&.{.soft_float}),
        },
        .cpu_features_sub = switch (arch) {
            .x86_64 => std.Target.x86.featureSet(&.{ .sse, .sse2, .mmx, .avx, .avx2 }),
        },
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/main.zig"),
        .target = kernel_target,
        .optimize = optimize,
        .code_model = .kernel,
    });
    kernel.want_lto = false;
    kernel.setLinkerScript(b.path(b.fmt("kernel/arch/{s}/linker.ld", .{@tagName(arch)})));
    kernel.root_module.addImport("limine", b.dependency("limine-zig", .{}).module("limine"));

    const kernel_step = b.step("kernel", "Build the kernel");
    kernel_step.dependOn(&b.addInstallArtifact(kernel, .{}).step);

    const efi_boot_name = switch (arch) {
        .x86_64 => "BOOTX64.EFI",
    };

    const esp = b.addWriteFiles();
    _ = esp.addCopyFile(b.dependency("limine", .{}).path(efi_boot_name), b.fmt("EFI/BOOT/{s}", .{efi_boot_name}));
    _ = esp.addCopyFile(b.path("limine.conf"), "limine.conf");
    _ = esp.addCopyFile(kernel.getEmittedBin(), "kernel");

    const esp_step = b.step("esp", "Build the Efi System Partition");
    esp_step.dependOn(&b.addInstallDirectory(.{ .source_dir = esp.getDirectory(), .install_dir = .prefix, .install_subdir = "esp" }).step);

    const hdd_cmd = b.addSystemCommand(&.{"sh"});
    hdd_cmd.addFileArg(b.path("scripts/mkhdd.sh"));
    hdd_cmd.addDirectoryArg(esp.getDirectory());
    const hdd = hdd_cmd.addOutputFileArg("image.hdd");

    const run_cmd = b.addSystemCommand(&.{switch (arch) {
        .x86_64 => "qemu-system-x86_64",
    }});

    run_cmd.addArg("-bios");
    run_cmd.addFileArg(b.dependency("edk2", .{}).path(b.fmt("bin/{s}", .{switch (arch) {
        .x86_64 => "RELEASEX64_OVMF.fd",
    }})));

    switch (arch) {
        .x86_64 => {
            // ...
        },
    }

    run_cmd.addArg("-hda");
    run_cmd.addFileArg(hdd);

    run_cmd.addArg("-debugcon");
    run_cmd.addArg("stdio");

    if (b.option(bool, "qemu_debug", "Enable QEMU debug logs") orelse false) {
        run_cmd.addArg("-d");
        run_cmd.addArg("int");
    }

    if (b.option(bool, "qemu_gdb", "Enable debugging via GDB in QEMU") orelse false) {
        run_cmd.addArg("-s");
        run_cmd.addArg("-S");
        run_cmd.step.dependOn(kernel_step);
    }

    run_cmd.addArg("-smp");
    run_cmd.addArg(b.fmt("{d}", .{b.option(usize, "smp", "Number of SMP cores to use") orelse 2}));

    const run_step = b.step("run", "Run in QEMU");
    run_step.dependOn(&run_cmd.step);

    b.default_step = kernel_step;
}
