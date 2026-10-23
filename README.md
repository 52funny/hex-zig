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
    const dependency = b.dependency("hex_zig", .{
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
    exe.root_module.addImport("hex_zig", dependency.module("hex_zig"));
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

Public API:

```zig
pub const Case = enum { upper, lower };
pub fn encodeHex(alloc: std.mem.Allocator, input: []const u8, case: Case) []u8;
pub fn decodeHex(alloc: std.mem.Allocator, input: []const u8) ![]u8;
```

- `encodeHex` produces two hexadecimal characters per input byte. It panics if allocation fails.
- `decodeHex` accepts `0-9`, `a-f`, and `A-F`. It returns `error.InvalidHexLength` for odd-length input, `error.InvalidCharacter` for invalid characters, or `error.OutOfMemory` if allocation fails.
- Both functions accept empty input without allocating. Free the returned slices with the same allocator, including empty slices.

## Development

Run these commands from this repository's root directory:

```sh
zig build                                    # Compile the library and its tests
zig build test                               # Run unit tests
zig build test -Doptimize=ReleaseFast         # Run tests in ReleaseFast mode
zig build example                            # Run the usage example
zig build bench -Doptimize=ReleaseFast        # Run benchmarks
```

See [examples/basic.zig](examples/basic.zig) for a complete example. The library is distributed as a Zig source module and used through `@import("hex_zig")`.
