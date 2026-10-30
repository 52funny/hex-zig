# hex-zig

A SIMD-accelerated hexadecimal encoding and decoding library for Zig. Supports uppercase and lowercase encoding and mixed-case decoding. The SIMD vector width is selected for the compilation target, with scalar code handling remaining bytes.

Requires **Zig 0.17.0**. The module is named `hex_zig` and has no third-party dependencies.

## Installation

Add [hex-zig](https://github.com/52funny/hex-zig) to your project by running this command from your project's root directory:

```sh
zig fetch --save=hex_zig git+https://github.com/52funny/hex-zig.git
```

Zig adds the dependency to `build.zig.zon` and records its package hash.

Import the module in your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const hex_zig = b.dependency("hex_zig", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("hex_zig", hex_zig.module("hex_zig"));
    b.installArtifact(exe);
}
```

## Usage

```zig
const std = @import("std");
const hex = @import("hex_zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;
    const case: hex.Case = .upper;

    const encoded = hex.encodeHex(alloc, "Hello", case);
    defer alloc.free(encoded);

    const decoded = try hex.decodeHex(alloc, encoded);
    defer alloc.free(decoded);

    std.debug.print("{s} -> {s}\n", .{ encoded, decoded });
    // 48656C6C6F -> Hello
}
```

To reuse existing buffers or use stack storage without allocating:

```zig
var encoded_buf: [10]u8 = undefined;
const encoded = try hex.encodeHexInto("Hello", &encoded_buf, .upper);
var decoded_buf: [5]u8 = undefined;
const decoded = try hex.decodeHexInto(encoded, &decoded_buf);
std.debug.print("{s} -> {s}\n", .{ encoded, decoded });
// 48656C6C6F -> Hello
```

Public API:

```zig
pub const Case = enum { upper, lower };
pub fn encodeHex(alloc: std.mem.Allocator, input: []const u8, case: Case) []u8;
pub fn encodeHexInto(input: []const u8, output: []u8, case: Case) error{BufferTooSmall}![]u8;
pub fn decodeHex(alloc: std.mem.Allocator, input: []const u8) ![]u8;
pub fn decodeHexInto(input: []const u8, output: []u8) error{ InvalidHexLength, BufferTooSmall, InvalidCharacter }![]u8;
```

Encoding produces two ASCII hexadecimal characters per input byte in the requested `Case` (`.upper` or `.lower`). For `encodeHex`, the encoded length must fit in `usize`. Decoding requires even-length input and accepts only `0-9`, `a-f`, and `A-F`, including mixed case; prefixes such as `0x`, separators, and whitespace are rejected. No function appends a null terminator.

`encodeHex` and `decodeHex` return owned slices. Free them with the same allocator, including empty results. Both accept empty input without allocating. `decodeHex` rejects odd-length input before allocating; otherwise it allocates before validating characters and frees the allocation on validation failure.

The `Into` functions never allocate. Input and output must not overlap. The output buffer may be larger than required: on success, the returned slice is exactly the written prefix of `output`, and the remaining bytes are unchanged. Its lifetime and ownership follow the original buffer; do not free the returned prefix independently. Empty input returns `output[0..0]` without writing, even when output capacity is zero.

`encodeHexInto` checks capacity before writing. `decodeHexInto` checks input length first, then capacity, then characters. Odd-length input returns `error.InvalidHexLength`; insufficient capacity returns `error.BufferTooSmall`. These length and capacity errors leave the buffer unchanged. Invalid characters return `error.InvalidCharacter` and may leave partially written output; discard that output after an error.

## Benchmarks

Sample results on an **AMD Ryzen 7 8845H**, Linux x86_64, using **Zig 0.17.0**, **ReleaseFast**, and a **64-byte SIMD vector width**.

To reproduce:

```sh
zig build bench -Doptimize=ReleaseFast
```

Each measurement reports the median of five samples. Throughput is measured in **GiB/s of input bytes**; decoding input sizes count hexadecimal characters. Allocations and frees use a `FixedBufferAllocator` backed by a reused scratch buffer.

### Encoding (lowercase)

The scalar reference uses a hexadecimal lookup table.

| Input size | Scalar (GiB/s) | hex-zig (GiB/s) | Speedup |
| --- | ---: | ---: | ---: |
| 16 B | 1.25 | 0.51 | 0.41x |
| 64 B | 1.73 | 6.62 | 3.82x |
| 1 KiB | 2.36 | 18.36 | 7.77x |
| 64 KiB | 2.40 | 39.95 | 16.63x |
| 1 MiB | 2.39 | 32.48 | 13.60x |

### Decoding

The reference uses `std.fmt.hexToBytes`. Input contains mixed-case hexadecimal characters.

| Input size | std.fmt.hexToBytes (GiB/s) | hex-zig (GiB/s) | Speedup |
| --- | ---: | ---: | ---: |
| 16 B | 1.90 | 1.90 | 1.00x |
| 64 B | 1.81 | 10.48 | 5.80x |
| 1 KiB | 1.37 | 29.19 | 21.36x |
| 64 KiB | 0.27 | 29.38 | 109.02x |
| 1 MiB | 0.22 | 28.59 | 128.27x |

Inputs shorter than the SIMD block use scalar code. These results describe one run on the machine above; throughput varies with hardware, CPU frequency, cache state, and system load.

## Development

Run these commands from this repository's root directory:

```sh
zig build                                     # Compile the library and its tests
zig build test                                # Run unit tests
zig build test -Doptimize=ReleaseFast         # Run tests in ReleaseFast mode
zig build example                             # Run the usage example
zig build bench -Doptimize=ReleaseFast        # Run benchmarks
```

See [examples/basic.zig](examples/basic.zig) for a complete example. The library is distributed as a Zig source module and used through `@import("hex_zig")`.
