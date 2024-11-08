const std = @import("std");

fn encoded_len(comptime T: type) u8 {
    switch (@typeInfo(T)) {
        .Int => {},
        else => @compileError("Expected unsigned integer type"),
    }

    return switch (@typeInfo(T).Int.bits) {
        8 => 2,
        16 => 3,
        32 => 5,
        64 => 10,
        128 => 19,
        else => @compileError("Expected any of u8, u16, u32, u64, or u128"),
    };
}

pub fn encode(comptime T: type, number: T) [encoded_len(T)]u8 {
    var out: [encoded_len(T)]u8 = [_]u8{0} ** encoded_len(T);
    var n = number;
    for (&out) |*b| {
        const b_: u8 = @truncate(n);
        b.* = b_ | 0x80;
        n >>= 7;
        if (n == 0) {
            b.* &= 0x7f;
            break;
        }
    }
    return out;
}

test "various encode" {
    try std.testing.expectEqual(encode(u8, 1), [2]u8{ 1, 0 });
    try std.testing.expectEqual(encode(u16, 127), [3]u8{ 127, 0, 0 });
    try std.testing.expectEqual(encode(u16, 128), [3]u8{ 128, 1, 0 });
    try std.testing.expectEqual(encode(u16, 255), [3]u8{ 255, 1, 0 });
    try std.testing.expectEqual(encode(u16, 300), [3]u8{ 172, 2, 0 });
    try std.testing.expectEqual(encode(u16, 16384), [3]u8{ 128, 128, 1 });
}
