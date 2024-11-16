const std = @import("std");

fn varintSize(comptime value: anytype) u32 {
    var count: u32 = 0;
    var v = value;

    while (v != 0) : (v >>= 7) {
        count += 1;
    }

    return if (count == 0) 1 else count;
}

fn encodedTypelen(comptime T: type) u8 {
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

fn encodedLen(comptime number: anytype) u8 {
    switch (@typeInfo(@TypeOf(number))) {
        .Int, .ComptimeInt => {},
        else => @compileError("Expected unsigned integer type"),
    }

    return varintSize(number);
}

fn encodedHexLen(comptime rawHexString: []const u8) u8 {
    const parsedHexString = if (std.mem.startsWith(u8, rawHexString, "0x"))
        rawHexString[2..]
    else
        rawHexString;

    const number = try std.fmt.parseInt(usize, parsedHexString, 16);

    return varintSize(number);
}

pub fn encodeForType(comptime T: type, number: T) [encodedTypelen(T)]u8 {
    var out: [encodedTypelen(T)]u8 = [_]u8{0} ** encodedTypelen(T);
    const n = number;
    doEncode(&out, n);
    return out;
}

pub fn encode(number: anytype) [encodedLen(number)]u8 {
    var out: [encodedLen(number)]u8 = [_]u8{0} ** encodedLen(number);
    const n: usize = number;
    doEncode(&out, n);
    return out;
}

fn doEncode(out: []u8, n_: anytype) void {
    var n = n_;
    for (out) |*b| {
        const b_: u8 = @truncate(n);
        b.* = b_ | 0x80;
        n >>= 7;
        if (n == 0) {
            b.* &= 0x7f;
            break;
        }
    }
}

fn doEncodeAlloc(allocator: std.mem.Allocator, number: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    var n: usize = number;
    while (true) {
        const b: u8 = @as(u8, @truncate(n)) | 0x80;
        try list.append(b);
        n >>= 7;
        if (n == 0) {
            list.items[list.items.len - 1] &= 0x7f; // Clear the MSB of the last byte
            break;
        }
    }

    return try list.toOwnedSlice();
}

pub fn encodeHexAlloc(allocator: std.mem.Allocator, number: anytype) ![]u8 {
    switch (@typeInfo(@TypeOf(number))) {
        .Int, .ComptimeInt => {},
        else => @compileError("Expected numeric value"),
    }
    return try doEncodeAlloc(allocator, number);
}

pub fn encodeHexStrAlloc(allocator: std.mem.Allocator, rawHexString: []const u8) ![]u8 {
    const parsedHexString = if (std.mem.startsWith(u8, rawHexString, "0x"))
        rawHexString[2..]
    else
        rawHexString;

    const number = try std.fmt.parseInt(usize, parsedHexString, 16);

    return try doEncodeAlloc(allocator, number);
}

pub fn encodeHexStr(comptime rawHexString: []const u8) ![encodedHexLen(rawHexString)]u8 {
    const out = comptime blk: {
        const parsedHexString = if (std.mem.startsWith(u8, rawHexString, "0x"))
            rawHexString[2..]
        else
            rawHexString;
        const number = try std.fmt.parseInt(usize, parsedHexString, 16);
        break :blk encode(number);
    };

    return out;
}

pub const DecodeResult = struct {
    code: usize,
    rest: []const u8,
};

pub const DecodeError = error{ NotMinimal, Insufficient };
pub fn decode(buf: []const u8) DecodeError!DecodeResult {
    var n: usize = 0;
    for (buf, 0..) |b, i| {
        const k: u8 = @intCast(b & 0x7F);
        n |= std.math.shl(usize, k, (i * 7));
        if ((b & 0x80) == 0) {
            // last bit
            if (b == 0 and i > 0) {
                return error.NotMinimal;
            }
            return .{ .code = n, .rest = buf[i + 1 ..] };
        }
    }
    return error.Insufficient;
}

test "encodeForType" {
    try std.testing.expectEqual(encodeForType(u8, 1), [2]u8{ 1, 0 });
    try std.testing.expectEqual(encodeForType(u16, 127), [3]u8{ 127, 0, 0 });
    try std.testing.expectEqual(encodeForType(u16, 128), [3]u8{ 128, 1, 0 });
    try std.testing.expectEqual(encodeForType(u16, 255), [3]u8{ 255, 1, 0 });
    try std.testing.expectEqual(encodeForType(u16, 300), [3]u8{ 172, 2, 0 });
    try std.testing.expectEqual(encodeForType(u16, 16384), [3]u8{ 128, 128, 1 });
    try std.testing.expectEqual(encodeForType(u64, std.math.maxInt(u64)), [10]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 });
}

test "encode" {
    const value = 1;
    try std.testing.expectEqual(encode(value), [1]u8{1});
    try std.testing.expectEqual(encode(127), [1]u8{127});
    try std.testing.expectEqual(encode(128), [2]u8{ 128, 1 });
    try std.testing.expectEqual(encode(255), [2]u8{ 255, 1 });
    try std.testing.expectEqual(encode(300), [2]u8{ 172, 2 });
    try std.testing.expectEqual(encode(3840), [2]u8{ 128, 30 });
    try std.testing.expectEqual(encode(16384), [3]u8{ 128, 128, 1 });
    try std.testing.expectEqual(encode(std.math.maxInt(u64)), [10]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 });
}

test "encodeHexAlloc" {
    {
        const encoded = try encodeHexAlloc(std.testing.allocator, 0x0001);
        defer std.testing.allocator.free(encoded);
        try std.testing.expect(std.mem.eql(u8, encoded, &[1]u8{1}));
    }
    {
        const encoded = try encodeHexAlloc(std.testing.allocator, 0x00);
        defer std.testing.allocator.free(encoded);
        try std.testing.expect(std.mem.eql(u8, encoded, &[1]u8{0}));
    }
}

test "encodeHexStrAlloc" {
    {
        const encoded = try encodeHexStrAlloc(std.testing.allocator, "0x0001");
        defer std.testing.allocator.free(encoded);
        try std.testing.expect(std.mem.eql(u8, encoded, &[1]u8{1}));
    }
    {
        const encoded = try encodeHexStrAlloc(std.testing.allocator, "0x00");
        defer std.testing.allocator.free(encoded);
        try std.testing.expect(std.mem.eql(u8, encoded, &[1]u8{0}));
    }
}

test "encodeHexStr" {
    try std.testing.expectEqual(try encodeHexStr("1"), [1]u8{1});
    try std.testing.expectEqual(try encodeHexStr("0x0001"), [1]u8{1});
    try std.testing.expectEqual(try encodeHexStr("7F"), [1]u8{127});
    try std.testing.expectEqual(try encodeHexStr("0x7F"), [1]u8{127});
    try std.testing.expectEqual(try encodeHexStr("80"), [2]u8{ 128, 1 });
    try std.testing.expectEqual(try encodeHexStr("0x0080"), [2]u8{ 128, 1 });
    try std.testing.expectEqual(try encodeHexStr("FF"), [2]u8{ 255, 1 });
    try std.testing.expectEqual(try encodeHexStr("0xFF"), [2]u8{ 255, 1 });
    try std.testing.expectEqual(try encodeHexStr("0x12C"), [2]u8{ 172, 2 });
    try std.testing.expectEqual(try encodeHexStr("0x012C"), [2]u8{ 172, 2 });
    try std.testing.expectEqual(try encodeHexStr("4000"), [3]u8{ 128, 128, 1 });
    try std.testing.expectEqual(try encodeHexStr("0x4000"), [3]u8{ 128, 128, 1 });
    try std.testing.expectEqual(try encodeHexStr("FFFFFFFFFFFFFFFF"), [10]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 });
    try std.testing.expectEqual(try encodeHexStr("0xFFFFFFFFFFFFFFFF"), [10]u8{ 255, 255, 255, 255, 255, 255, 255, 255, 255, 1 });
}

test "encodeHexStr==encodeHexStrAlloc" {
    const encode_without_alloc = try encodeHexStr("0xFFFFFFFFFFFFFFFF");
    const encoded_with_alloc = try encodeHexStrAlloc(std.testing.allocator, "0xFFFFFFFFFFFFFFFF");
    defer std.testing.allocator.free(encoded_with_alloc);
    try std.testing.expect(std.mem.eql(u8, &encode_without_alloc, encoded_with_alloc));
}

test "decode" {
    {
        const buf = ([1]u8{1});
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 1);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        const buf = ([1]u8{0b0111_1111});
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 127);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        const buf = ([2]u8{ 0b1000_0000, 1 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 128);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        // encode with remaining data.
        const buf = ([3]u8{ 0b1000_0000, 1, 0b1000_0000 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 128);
        try std.testing.expectEqual(decoded.rest[0], 0b1000_0000);
    }
    {
        const buf = ([2]u8{ 0b1000_0000, 1 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 128);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        const buf = ([2]u8{ 0b1111_1111, 1 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 255);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        const buf = ([3]u8{ 0x80, 0x80, 1 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 16384);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        const buf = ([2]u8{ 0b1010_1100, 0b0000_0010 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 300);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    {
        const buf = ([10]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 1 });
        const decoded = (try decode(buf[0..]));
        try std.testing.expectEqual(decoded.code, 0xFFFFFFFFFFFFFFFF);
        try std.testing.expectEqual(decoded.rest.len, 0);
    }
    // errors.
    {
        const buf = ([9]u8{ 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80 });
        try std.testing.expectError(DecodeError.Insufficient, decode(buf[0..]));
    }
}

test "identity" {
    {
        for (0..std.math.maxInt(u8)) |n_| {
            const n: u8 = @intCast(n_);
            try std.testing.expectEqual(n, (try decode(&encodeForType(u8, n))).code);
        }
    }
    {
        for (0..std.math.maxInt(u16)) |n_| {
            const n: u16 = @intCast(n_);
            try std.testing.expectEqual(n, (try decode(&encodeForType(u16, n))).code);
        }
    }
    {
        for (0..1000_000) |n_| {
            const n: u32 = @intCast(n_);
            try std.testing.expectEqual(n, (try decode(&encodeForType(u32, n))).code);
        }
    }
    {
        for (0..1000_000) |n_| {
            const n: u64 = @intCast(n_);
            try std.testing.expectEqual(n, (try decode(&encodeForType(u64, n))).code);
        }
    }
    {
        for (0..1000_000) |n_| {
            const n: u128 = @intCast(n_);
            try std.testing.expectEqual(n, (try decode(&encodeForType(u128, n))).code);
        }
    }
}
