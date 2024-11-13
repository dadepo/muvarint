const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const filters = b.option([]const []const u8, "filter", "Filters test");

    const opts = .{ .target = target, .optimize = optimize };
    const zbench_module = b.dependency("zbench", opts).module("zbench");

    const lib = b.addStaticLibrary(.{
        .name = "muvarint",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("zbench", zbench_module);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .filters = filters orelse &.{},
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const bench_step = b.step("bench", "Run benchmarks");
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/benchmark.zig" } },
        .target = target,
        .optimize = optimize,
    });
    const install_bench = b.addInstallArtifact(bench, .{});
    bench.root_module.addImport("zbench", zbench_module);
    bench_step.dependOn(&bench.step);
    bench_step.dependOn(&install_bench.step);

    _ = b.addModule("muvarint", .{
        .root_source_file = b.path("src/lib.zig"),
    });
}
