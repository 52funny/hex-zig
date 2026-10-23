//! SIMD-accelerated hexadecimal encoding and decoding.
//! Free returned slices with the allocator passed to the conversion function.

const std = @import("std");

const vector_length = std.simd.suggestVectorLength(u8);
const block_size = vector_length orelse 16;
const ByteBlock = @Vector(block_size, u8);

/// Letter case used when encoding hexadecimal digits.
pub const Case = enum {
    upper,
    lower,
};

const alphabet_lower = "0123456789abcdef";
const alphabet_upper = "0123456789ABCDEF";

/// Encodes bytes as ASCII hexadecimal in the requested case, using two characters per byte.
/// The caller owns the returned slice and must free it with `alloc`.
/// Empty input requires no allocation. Panics if allocation fails.
pub fn encodeHex(alloc: std.mem.Allocator, input: []const u8, case: Case) []u8 {
    if (input.len == 0) return "";
    const output = alloc.alloc(u8, input.len * 2) catch @panic("Out of memory");

    var i: usize = 0;
    if (vector_length != null) {
        while (input.len - i >= block_size) : (i += block_size) {
            const bytes: ByteBlock = input[i..][0..block_size].*;
            const hi = nibblesToHex(bytes >> @splat(4), case);
            const lo = nibblesToHex(bytes & @as(ByteBlock, @splat(0x0f)), case);
            output[i * 2 ..][0 .. block_size * 2].* = std.simd.interlace(.{ hi, lo });
        }
    }

    const alphabet = if (case == .upper) alphabet_upper else alphabet_lower;
    while (i < input.len) : (i += 1) {
        output[i * 2] = alphabet[input[i] >> 4];
        output[i * 2 + 1] = alphabet[input[i] & 0x0f];
    }
    return output;
}

fn nibblesToHex(nibbles: ByteBlock, case: Case) ByteBlock {
    const is_digit = nibbles < @as(ByteBlock, @splat(10));
    const result = blk: switch (case) {
        inline .upper => break :blk nibbles + @select(u8, is_digit, @as(ByteBlock, @splat('0')), @as(ByteBlock, @splat('A' - 10))),
        inline .lower => break :blk nibbles + @select(u8, is_digit, @as(ByteBlock, @splat('0')), @as(ByteBlock, @splat('a' - 10))),
    };
    return result;
}

/// Decodes ASCII hexadecimal, accepting both uppercase and lowercase letters.
/// The caller owns the returned slice and must free it with `alloc`.
/// Returns `InvalidHexLength`, `InvalidCharacter`, or `OutOfMemory` on failure.
/// Empty input requires no allocation.
pub fn decodeHex(alloc: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len % 2 != 0) {
        return error.InvalidHexLength;
    }

    const output = try alloc.alloc(u8, input.len / 2);
    errdefer alloc.free(output);

    var i: usize = 0;
    if (vector_length != null) {
        const even = comptime std.simd.iota(i32, block_size / 2) * @as(@Vector(block_size / 2, i32), @splat(2));
        const odd = comptime even + @as(@Vector(block_size / 2, i32), @splat(1));

        while (input.len - i >= block_size) : (i += block_size) {
            const chars: ByteBlock = input[i..][0..block_size].*;
            // Wrapping subtraction makes bytes outside either range fail the
            // unsigned comparisons, including non-ASCII bytes.
            const digits = chars -% @as(ByteBlock, @splat('0'));
            const letters = (chars | @as(ByteBlock, @splat(0x20))) -% @as(ByteBlock, @splat('a'));
            const is_digit = digits <= @as(ByteBlock, @splat(9));
            const is_letter = letters <= @as(ByteBlock, @splat(5));
            if (!@reduce(.And, is_digit | is_letter)) return error.InvalidCharacter;

            const nibbles = @select(u8, is_digit, digits, letters +% @as(ByteBlock, @splat(10)));
            const hi = @shuffle(u8, nibbles, undefined, even);
            const lo = @shuffle(u8, nibbles, undefined, odd);
            output[i / 2 ..][0 .. block_size / 2].* = (hi << @splat(4)) | lo;
        }
    }

    // Handle short inputs, the remainder, and targets without SIMD support.
    while (i < input.len) : (i += 2) {
        const hi = try std.fmt.charToDigit(input[i], 16);
        const lo = try std.fmt.charToDigit(input[i + 1], 16);
        output[i / 2] = (hi << 4) | lo;
    }

    return output;
}

test "encodeHex accepts empty input and emits lowercase hex" {
    const alloc = std.testing.allocator;
    const empty = encodeHex(alloc, "", .lower);
    defer alloc.free(empty);
    try std.testing.expectEqualSlices(u8, "", empty);

    const encoded = encodeHex(alloc, "\x00\x01\x09\x0a\x0f\x10\x7f\x80\xab\xcd\xef\xffHello", .lower);
    defer alloc.free(encoded);
    try std.testing.expectEqualSlices(u8, "0001090a0f107f80abcdefff48656c6c6f", encoded);
}

test "encodeHex handles every byte value in both cases across SIMD lanes and the scalar tail" {
    const alloc = std.testing.allocator;
    var input: [block_size * 2 + 1]u8 = undefined;
    for (0..256) |value| {
        @memset(&input, @intCast(value));
        const lower = std.fmt.bytesToHex(input, .lower);
        const upper = std.fmt.bytesToHex(input, .upper);
        for ([_]Case{ .lower, .upper }) |case| {
            const expected: []const u8 = if (case == .upper) &upper else &lower;
            const encoded = encodeHex(alloc, &input, case);
            defer alloc.free(encoded);
            try std.testing.expectEqualSlices(u8, expected, encoded);
        }
    }
}

test "encodeHex handles both cases across SIMD boundaries, unaligned input, and round trips" {
    const alloc = std.testing.allocator;
    const input_len = block_size * 3 + 17;
    var storage: [input_len + 3]u8 = undefined;
    for (0..4) |offset| {
        const input = storage[offset..][0..input_len];
        for (input, 0..) |*byte, i| byte.* = @truncate(i * 73 + offset * 17);
        const lower = std.fmt.bytesToHex(input.*, .lower);
        const upper = std.fmt.bytesToHex(input.*, .upper);

        for ([_]Case{ .lower, .upper }) |case| {
            const expected: []const u8 = if (case == .upper) &upper else &lower;
            for (0..input.len + 1) |len| {
                const encoded = encodeHex(alloc, input[0..len], case);
                defer alloc.free(encoded);
                try std.testing.expectEqualSlices(u8, expected[0 .. len * 2], encoded);

                const decoded = try decodeHex(alloc, encoded);
                defer alloc.free(decoded);
                try std.testing.expectEqualSlices(u8, input[0..len], decoded);
            }
        }
    }
}

test "encodeHex needs no allocation for empty input in either case" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const alloc = failing.allocator();
    for ([_]Case{ .lower, .upper }) |case| {
        const empty = encodeHex(alloc, "", case);
        defer alloc.free(empty);
        try std.testing.expectEqualSlices(u8, "", empty);
        try std.testing.expect(!failing.has_induced_failure);
    }
}

test "decodeHex accepts empty input and mixed case" {
    const alloc = std.testing.allocator;
    const empty = try decodeHex(alloc, "");
    defer alloc.free(empty);
    try std.testing.expectEqualSlices(u8, "", empty);

    const decoded = try decodeHex(alloc, "00019aAbBcCdDeEfFf48656c6c6f");
    defer alloc.free(decoded);
    try std.testing.expectEqualSlices(u8, "\x00\x01\x9a\xab\xbc\xcd\xde\xef\xffHello", decoded);
}

test "decodeHex handles SIMD boundaries and unaligned input" {
    const alloc = std.testing.allocator;
    var expected: [block_size * 3 + 17]u8 = undefined;
    for (&expected, 0..) |*byte, i| byte.* = @truncate(i * 73);
    var encoded = std.fmt.bytesToHex(expected, .lower);
    for (&encoded, 0..) |*char, i| {
        if (i % 3 == 0) char.* = std.ascii.toUpper(char.*);
    }

    var storage: [encoded.len + 3]u8 = undefined;
    for (0..4) |offset| {
        const input = storage[offset..][0..encoded.len];
        @memcpy(input, &encoded);
        for (0..expected.len + 1) |len| {
            const decoded = try decodeHex(alloc, input[0 .. len * 2]);
            defer alloc.free(decoded);
            try std.testing.expectEqualSlices(u8, expected[0..len], decoded);
        }
    }
}

test "decodeHex checks every byte value in every SIMD lane and the scalar tail" {
    const alloc = std.testing.allocator;
    var input: [block_size * 2 + 2]u8 = @splat('0');
    var expected: [input.len / 2]u8 = undefined;

    for (0..256) |value| {
        for (0..input.len) |position| {
            input[position] = @intCast(value);
            defer input[position] = '0';

            // Use the standard decoder as an independent reference.
            const reference = std.fmt.hexToBytes(&expected, &input) catch {
                try std.testing.expectError(error.InvalidCharacter, decodeHex(alloc, &input));
                continue;
            };
            const decoded = try decodeHex(alloc, &input);
            defer alloc.free(decoded);
            try std.testing.expectEqualSlices(u8, reference, decoded);
        }
    }
}

test "decodeHex rejects odd lengths before allocating" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const alloc = failing.allocator();
    try std.testing.expectError(error.InvalidHexLength, decodeHex(alloc, "0"));
    try std.testing.expectError(error.InvalidHexLength, decodeHex(alloc, "000"));
    try std.testing.expectError(error.InvalidHexLength, decodeHex(alloc, &@as([block_size + 1]u8, @splat('0'))));
    try std.testing.expect(!failing.has_induced_failure);
}

test "decodeHex propagates allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, decodeHex(failing.allocator(), "00"));
}
