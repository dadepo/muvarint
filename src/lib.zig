const std = @import("std");

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

pub fn varintSize(value: anytype) u32 {
    var count: u32 = 0;
    var v = value;

    while (v != 0) : (v >>= 7) {
        count += 1;
    }

    return if (count == 0) 1 else count;
}

pub fn encode(number: anytype) [encodedLen(number)]u8 {
    var out: [encodedLen(number)]u8 = [_]u8{0} ** encodedLen(number);
    const n: usize = number;
    doEncode(n, &out);
    return out;
}

fn doEncode(n_: anytype, out: []u8) void {
    var n = n_;
    for (out) |*b| {
        // get the lsb.
        const lsb: u8 = @truncate(n);
        // Set the most significant bit of the lsb to 1 and save that as the output byte in this iteration.
        // output byte = lsb | 10000000
        b.* = lsb | 0x80;
        // Now shift the number being encoded to the right by 7 bits to remove the lsb that was processed.
        n >>= 7;
        if (n == 0) {
            // if after the shift, n = 0, we are at the end,
            // then set the most significant bit of the lsb back to 0 and exit the loop.
            b.* &= 0x7f;
            break;
        }
    }
}

pub fn bufferEncode(number: anytype, out: []u8) !void {
    const len = varintSize(number);
    if (out.len < len) {
        return error.InsufficientOutputBuffer;
    }
    if (out.len > len) {
        return error.ExcessOutputBuffer;
    }
    doEncode(number, out);
}

pub fn bufferEncodeHex(number: anytype, out: []u8) !void {
    switch (@typeInfo(@TypeOf(number))) {
        .Int, .ComptimeInt => {},
        else => @compileError("Expected numeric value"),
    }
    return try bufferEncode(number, out);
}

pub fn bufferEncodeHexStr(rawHexString: []const u8, out: []u8) !void {
    const parsedHexString = if (std.mem.startsWith(u8, rawHexString, "0x"))
        rawHexString[2..]
    else
        rawHexString;

    const number = try std.fmt.parseInt(usize, parsedHexString, 16);

    return try bufferEncode(number, out);
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

test "bufferEncodeHex" {
    {
        const to_encode: usize = 0x0001;
        var encoded = try std.BoundedArray(u8, 64).init(varintSize(to_encode));
        try bufferEncodeHex(to_encode, encoded.slice());
        try std.testing.expect(std.mem.eql(u8, encoded.slice(), &[1]u8{1}));
    }
    {
        const to_encode: usize = 0x00;
        var encoded = try std.BoundedArray(u8, 64).init(varintSize(to_encode));
        try bufferEncodeHex(to_encode, encoded.slice());
        try std.testing.expect(std.mem.eql(u8, encoded.slice(), &[1]u8{0}));
    }
}

test "bufferEncodeHexStr" {
    {
        const to_encode = "0x0001";
        const size: usize = 0x0001;
        var encoded = try std.BoundedArray(u8, 64).init(varintSize(size));
        try bufferEncodeHexStr(to_encode, encoded.slice());
        try std.testing.expect(std.mem.eql(u8, encoded.slice(), &[1]u8{1}));
    }
    {
        const to_encode = "0x00";
        const size: usize = 0x00;
        var encoded = try std.BoundedArray(u8, 64).init(varintSize(size));
        try bufferEncodeHexStr(to_encode, encoded.slice());
        try std.testing.expect(std.mem.eql(u8, encoded.slice(), &[1]u8{0}));
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

test "encodeHexStr==bufferEncodeHexStr" {
    const encode_without_buffer = try encodeHexStr("0xFFFFFFFFFFFFFFFF");
    const to_encode = "0xFFFFFFFFFFFFFFFF";
    const size: usize = 0xFFFFFFFFFFFFFFFF;
    var encoded_with_buffer = try std.BoundedArray(u8, 128).init(varintSize(size));
    try bufferEncodeHexStr(to_encode, encoded_with_buffer.slice());
    try std.testing.expect(std.mem.eql(u8, &encode_without_buffer, encoded_with_buffer.slice()));
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

test "identity-bufferEncode" {
    {
        for (0..std.math.maxInt(u8)) |n_| {
            const n: u8 = @intCast(n_);
            var out = try std.BoundedArray(u8, 64).init(varintSize(n));
            try bufferEncode(n, out.slice());
            try std.testing.expectEqual(n, (try decode(out.slice())).code);
        }
    }
    {
        for (0..std.math.maxInt(u16)) |n_| {
            const n: u16 = @intCast(n_);
            var out = try std.BoundedArray(u8, 64).init(varintSize(n));
            try bufferEncode(n, out.slice());
            try std.testing.expectEqual(n, (try decode(out.slice())).code);
        }
    }
    {
        for (0..1000_000) |n_| {
            const n: u32 = @intCast(n_);
            var out = try std.BoundedArray(u8, 64).init(varintSize(n));
            try bufferEncode(n, out.slice());
            try std.testing.expectEqual(n, (try decode(out.slice())).code);
        }
    }
    {
        for (0..1000_000) |n_| {
            const n: u64 = @intCast(n_);
            var out = try std.BoundedArray(u8, 64).init(varintSize(n));
            try bufferEncode(n, out.slice());
            try std.testing.expectEqual(n, (try decode(out.slice())).code);
        }
    }
    {
        for (0..1000_000) |n_| {
            const n: u128 = @intCast(n_);
            var out = try std.BoundedArray(u8, 64).init(varintSize(n));
            try bufferEncode(n, out.slice());
            try std.testing.expectEqual(n, (try decode(out.slice())).code);
        }
    }
}
