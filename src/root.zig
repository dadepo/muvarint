const std = @import("std");

fn encodedlen(comptime T: type) u8 {
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

pub fn encode(comptime T: type, number: T) [encodedlen(T)]u8 {
    var out: [encodedlen(T)]u8 = [_]u8{0} ** encodedlen(T);
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

pub const DecodeError = error{ NotMinimal, Overflow, Insufficient };
pub fn decode(comptime T: type, buf: []const u8) DecodeError!T {
    var n: T = 0;
    for (buf, 0..) |b, i| {
        const k: u8 = @intCast(b & 0x7F);
        n |= std.math.shl(T, k, (i * 7));
        if ((b & 0x80) == 0) {
            // last bit
            if (b == 0 and i > 0) {
                return error.NotMinimal;
            }
            return n;
        }
        if (i == (encodedlen(T) - 1)) {
            return error.Overflow;
        }
    }
    return error.Insufficient;
}

test "encode" {
    try std.testing.expectEqual(encode(u8, 1), [2]u8{ 1, 0 });
    try std.testing.expectEqual(encode(u16, 127), [3]u8{ 127, 0, 0 });
    try std.testing.expectEqual(encode(u16, 128), [3]u8{ 128, 1, 0 });
    try std.testing.expectEqual(encode(u16, 255), [3]u8{ 255, 1, 0 });
    try std.testing.expectEqual(encode(u16, 300), [3]u8{ 172, 2, 0 });
    try std.testing.expectEqual(encode(u16, 16384), [3]u8{ 128, 128, 1 });
    try std.testing.expectEqual(encode(u64, std.math.maxInt(u64)), [10]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 });
}

test "decode" {
    {
        const buf = ([1]u8{1});
        try std.testing.expectEqual(try decode(u8, buf[0..]), 1);
    }
    {
        const buf = ([1]u8{0b0111_1111});
        try std.testing.expectEqual(try decode(u8, buf[0..]), 127);
    }
    {
        const buf = ([2]u8{ 0b1000_0000, 1 });
        try std.testing.expectEqual(try decode(u8, buf[0..]), 128);
    }
    {
        const buf = ([2]u8{ 0b1000_0000, 1 });
        try std.testing.expectEqual(try decode(u8, buf[0..]), 128);
    }
    {
        const buf = ([2]u8{ 0b1111_1111, 1 });
        try std.testing.expectEqual(try decode(u8, buf[0..]), 255);
    }
    {
        const buf = ([3]u8{ 0x80, 0x80, 1 });
        try std.testing.expectEqual(try decode(u16, buf[0..]), 16384);
    }
    {
        const buf = ([2]u8{ 0b1010_1100, 0b0000_0010 });
        try std.testing.expectEqual(try decode(u16, buf[0..]), 300);
    }
    {
        const buf = ([10]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 1 });
        try std.testing.expectEqual(try decode(u64, buf[0..]), 0xFFFFFFFFFFFFFFFF);
    }
    // errors.
    {
        const buf = ([10]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 });
        try std.testing.expectError(DecodeError.Overflow, decode(u64, buf[0..]));
    }
    {
        const buf = ([9]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 });
        try std.testing.expectError(DecodeError.Insufficient, decode(u64, buf[0..]));
    }
}
