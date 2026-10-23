const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const library = b.addModule("hex_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .name = "hex-zig-tests",
        .root_module = library,
    });
    const check_step = b.step("check", "Compile the library and its tests");
    check_step.dependOn(&unit_tests.step);
    b.default_step = check_step;

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    const example = b.addExecutable(.{
        .name = "hex-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "hex_zig", .module = library }},
        }),
    });
    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run the basic library usage example");
    example_step.dependOn(&run_example.step);

    const bench = b.addExecutable(.{
        .name = "hex-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "hex_zig", .module = library }},
        }),
    });
    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Compare SIMD hex encoding and decoding with scalar implementations (use -Doptimize=ReleaseFast)");
    bench_step.dependOn(&run_bench.step);
}
