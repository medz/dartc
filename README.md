# dartc

A native Dart compiler written in Dart.

`dartc` is experimental and self-hosting. It compiles a Dart subset directly to ARM64 machine code for macOS and Linux. Generated executables do not require the Dart SDK, VM, or snapshots.

## Install

```sh
dart pub global activate dartc
```

## Build and run

Requires Dart 3.13 or later. Self-hosting is supported on macOS and Linux ARM64.

```sh
git clone https://github.com/medz/dartc.git
cd dartc
dart pub get
dart run bin/dartc.dart example/hello.dart -o build/hello
./build/hello
```

## Supported Dart

- Top-level functions and variables, direct calls, and recursion.
- Integers, booleans, strings, and typed lists.
- Local variables, assignments, arithmetic, comparisons, and short-circuit logic.
- `if`, `while`, `do`/`while`, three-part `for`, list `for`/`in`, labelled jumps, constant `switch` cases, and `return`.
- Basic string and list operations, Unicode strings, interpolation, `print`, and command-line arguments.
- Relative source imports and exports, prefixes, private names, and `show`/`hide` filters.

The source checkout additionally supports simple classes with fields, field-formal constructors, getters, and directly resolved instance methods, nested typed lists, and lazy top-level initialization. Instance members may be used with or without `this`. Basic `dynamic`, `Object`, `null`, and nullable values retain their runtime types across assignments, calls, fields, and list storage. Runtime `is`, `is!`, and `as` check supported value types and reified list arguments. List covariance checks writes against the actual element type. Interpolation and `print` support lists and class `toString` overrides, including cyclic lists.

The `StringBuffer` subset supports empty construction, String arguments to `write` and `writeln`, `clear`, `length`, `isEmpty`, and `toString`. Indexed list access checks bounds. `List.filled` honors `growable`, which defaults to `false`; fixed-length lists allow element replacement and reject `add`, `removeLast`, and `clear`. Lists must not change length during `for`/`in` iteration; concurrent modification errors are not yet implemented.

String indices and positions use UTF-16 code units and check ranges. `String.fromCharCodes` currently takes one `List<int>` argument, with codes from 0 through `0x10ffff`; surrogate code units are preserved.

Inheritance, general dynamic member calls, closures, exceptions, async code, and most SDK libraries are not yet supported. Failed runtime type checks terminate the process; exception handling and stack unwinding are not implemented. Runtime memory is currently reclaimed when the process exits. Self-hosting does not imply full Dart language compatibility.

## Build a standalone compiler

```sh
dart run tool/bootstrap.dart
build/dartc-stage2 example/hello.dart -o build/hello
```

The bootstrap command starts from the previously verified local `build/dartc-seed`. Only when that file is absent does it use official Dart to build the initial seed. It then rebuilds with native `dartc`, compares repeated builds, and checks behavior against official Dart. A successful run updates the local native seed; a failed run preserves it. Use `--seed /path/to/dartc` to select an existing native compiler explicitly.

Official AOT builds can be used as a separate, opt-in performance reference:

```sh
dart run tool/benchmark.dart
```

This compares the same compiler task and writes measurements to `build/benchmark.json`. Reference binaries do not become bootstrap seeds. CI runs only when manually dispatched during compiler development.

The native compiler uses `lib/src/runtime.dart` as its standard-runtime source. When placing the compiler outside the repository, supply its location:

```sh
dartc program.dart -o program --std /path/to/dartc/lib/src/runtime.dart
```

The compiler and runtime source must use the same ABI. Rebuild the compiler when updating the runtime source.

The compiler writes ARM64 instructions, Mach-O, ELF, archives, and local Mach-O signatures in Dart. No C compiler, assembler, linker, or signing subprocess is required.

## Cross-compile

Choose the target explicitly when it differs from the host:

```sh
build/dartc-stage2 example/hello.dart --target linux-arm64 -o build/hello-linux
build/dartc-stage2 example/hello.dart --target macos-arm64 -o build/hello-macos
```

Only ARM64 targets are currently supported.

## Native libraries

Experimental macOS ARM64 library output uses explicit FFI callback signatures. The current subset accepts `Int64` parameters and results; it does not infer native types from ordinary Dart types.

```dart
import 'dart:ffi';

typedef AddNative = Int64 Function(Int64, Int64);
int addImpl(int a, int b) => a + b;
final add = Pointer.fromFunction<AddNative>(addImpl, 0);
```

Export the named FFI binding:

```sh
build/dartc-stage2 example/math.dart --emit dylib --export add -o build/libmath.dylib
build/dartc-stage2 example/math.dart --emit static --export add -o build/libmath.a
```

`--emit object` writes a Mach-O target file. Library functions currently support integer computation and direct calls, without global state, allocation, or a Dart runtime context. Callers declare the corresponding native signature, for example `int64_t add(int64_t, int64_t)` in C. Linux library output is not yet supported.

## Verify program behavior

```sh
dart run test/behavior_test.dart
dart run test/library_test.dart build/dartc-stage2
```

The compiler architecture is described in [doc/architecture.md](doc/architecture.md).

MIT licensed.
