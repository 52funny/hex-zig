const std = @import("std");
const builtin = @import("builtin");
const hex = @import("hex_zig");

fn encodeHexScalar(alloc: std.mem.Allocator, input: []const u8) ![]u8 {
    const output_len = std.math.mul(usize, input.len, 2) catch return error.OutOfMemory;
    const output = try alloc.alloc(u8, output_len);
    const alphabet = "0123456789abcdef";
    for (input, 0..) |byte, i| {
        output[i * 2] = alphabet[byte >> 4];
        output[i * 2 + 1] = alphabet[byte & 0x0f];
    }
    return output;
}

fn encodeHexSimd(alloc: std.mem.Allocator, input: []const u8) ![]u8 {
    return hex.encodeHex(alloc, input, .lower);
}

fn decodeHexScalar(alloc: std.mem.Allocator, input: []const u8) ![]u8 {
    if (input.len % 2 != 0) return error.InvalidHexLength;
    const output = try alloc.alloc(u8, input.len / 2);
    errdefer alloc.free(output);
    return std.fmt.hexToBytes(output, input);
}

fn measure(
    comptime convert: anytype,
    io: std.Io,
    input: []const u8,
    scratch: []u8,
) !f64 {
    var fixed = std.heap.FixedBufferAllocator.init(scratch);
    const alloc = fixed.allocator();
    const iterations = @max(100, 32 * 1024 * 1024 / input.len);
    var samples: [5]u64 = undefined;

    for (&samples) |*elapsed| {
        const start = std.Io.Clock.awake.now(io);
        for (0..iterations) |_| {
            std.mem.doNotOptimizeAway(input.ptr);
            const output = try convert(alloc, input);
            std.mem.doNotOptimizeAway(output.ptr);
            alloc.free(output);
        }
        elapsed.* = @intCast(start.durationTo(std.Io.Clock.awake.now(io)).toNanoseconds());
    }
    std.mem.sort(u64, &samples, {}, std.sort.asc(u64));
    // Median throughput in GiB/s, counting input bytes. Fixed-buffer allocation
    // keeps system allocation costs from masking the cost of conversion.
    return @as(f64, @floatFromInt(input.len * iterations)) /
        @as(f64, @floatFromInt(samples[samples.len / 2])) * (1e9 / @as(f64, 1024 * 1024 * 1024));
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const sizes = [_]usize{ 16, 64, 1024, 64 * 1024, 1024 * 1024 };
    const input = try alloc.alloc(u8, sizes[sizes.len - 1]);
    defer alloc.free(input);
    const scratch = try alloc.alloc(u8, input.len * 2);
    defer alloc.free(scratch);

    var prng = std.Random.DefaultPrng.init(0x12345678);
    prng.random().bytes(input);

    std.debug.print("{s}, SIMD width: {d} bytes; median of 5 samples, input GiB/s\n", .{
        @tagName(builtin.mode), std.simd.suggestVectorLength(u8) orelse 0,
    });
    {
        const expected = try encodeHexScalar(alloc, input);
        defer alloc.free(expected);
        const actual = hex.encodeHex(alloc, input, .lower);
        defer alloc.free(actual);
        if (!std.mem.eql(u8, expected, actual)) return error.IncorrectEncode;

        std.debug.print("encode bytes      scalar      SIMD    speedup\n", .{});
        for (sizes) |size| {
            const scalar = try measure(encodeHexScalar, init.io, input[0..size], scratch[0 .. size * 2]);
            const simd = try measure(encodeHexSimd, init.io, input[0..size], scratch[0 .. size * 2]);
            std.debug.print("{d: >11}    {d: >7.2}   {d: >7.2}    {d:.2}x\n", .{ size, scalar, simd, simd / scalar });
        }
    }

    const alphabet = "0123456789abcdefABCDEF";
    for (input) |*char| char.* = alphabet[char.* % alphabet.len];

    // Check both implementations agree before timing either of them.
    const expected = try decodeHexScalar(alloc, input);
    defer alloc.free(expected);
    const actual = try hex.decodeHex(alloc, input);
    defer alloc.free(actual);
    if (!std.mem.eql(u8, expected, actual)) return error.IncorrectDecode;

    std.debug.print("decode bytes     std.fmt      SIMD    speedup\n", .{});
    for (sizes) |size| {
        const scalar = try measure(decodeHexScalar, init.io, input[0..size], scratch[0 .. size / 2]);
        const simd = try measure(hex.decodeHex, init.io, input[0..size], scratch[0 .. size / 2]);
        std.debug.print("{d: >11}    {d: >7.2}   {d: >7.2}    {d:.2}x\n", .{ size, scalar, simd, simd / scalar });
    }
}
