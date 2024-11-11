const std = @import("std");
const zbench = @import("zbench");
const encode = @import("root.zig").encode;

fn encodeBenchmark(_: std.mem.Allocator) void {
    _ = encode(u64, std.math.maxInt(u64));
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var bench = zbench.Benchmark.init(std.heap.page_allocator, .{});
    defer bench.deinit();

    try bench.add("Encode Benchmark", encodeBenchmark, .{});

    try stdout.writeAll("\n\n");
    try bench.run(stdout);
}
