const std = @import("std");
const hex = @import("hex_zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const input = "Hello, Zig!";

    const lower = hex.encodeHex(alloc, input, .lower);
    defer alloc.free(lower);

    const case: hex.Case = .upper;
    const upper = hex.encodeHex(alloc, input, case);
    defer alloc.free(upper);

    const decoded = try hex.decodeHex(alloc, upper);
    defer alloc.free(decoded);

    std.debug.print("lower: {s}\nupper: {s}\ndecoded: {s}\n", .{ lower, upper, decoded });

    var encoded_buf: [input.len * 2]u8 = undefined;
    const encoded_into = try hex.encodeHexInto(input, &encoded_buf, .upper);
    var decoded_buf: [input.len]u8 = undefined;
    const decoded_into = try hex.decodeHexInto(encoded_into, &decoded_buf);
    std.debug.print("buffered: {s} -> {s}\n", .{ encoded_into, decoded_into });
}
