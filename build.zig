const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lmjcre_dep = b.dependency("lmjcore", .{});

    const lmjcore_module = lmjcre_dep.module("lmjcore");

    const exe = b.addExecutable(.{ .name = "LMJRouter", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });

    exe.root_module.addImport("lmjcore", lmjcore_module);
    exe.linkLibC();

    // 运行步骤
    const example_run = b.addRunArtifact(exe);
    const example_step = b.step("run", "Run example");
    example_step.dependOn(&example_run.step);

    b.installArtifact(exe);
}
