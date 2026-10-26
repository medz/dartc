# dartc

A native Dart compiler written in Dart.

`dartc` is experimental and self-hosting. It compiles a Dart subset directly to macOS ARM64 machine code. Generated executables do not require the Dart SDK, VM, or snapshots.

## Build and run

Requires Dart 3.13 or later and macOS on Apple Silicon.

```sh
git clone https://github.com/medz/dartc.git
cd dartc
dart pub get
dart run bin/dartc.dart example/hello.dart -o build/hello
./build/hello
```

The published `0.0.1` package supports the initial `main` and string-literal `print` subset. Use the repository for the compiler described below.

## Supported Dart

- Top-level functions and variables, direct calls, and recursion.
- Integers, booleans, strings, and typed lists.
- Local variables, assignments, arithmetic, comparisons, and short-circuit logic.
- `if`, `while`, three-part `for`, `break`, `continue`, and `return`.
- Basic string and list operations, Unicode strings, `print`, and command-line arguments.
- Relative source imports.

Classes, closures, exceptions, async code, and most SDK libraries are not yet supported. Top-level initialization is currently eager. Self-hosting does not imply full Dart language compatibility.

## Build a standalone compiler

```sh
dart run tool/bootstrap.dart
build/dartc-stage2 example/hello.dart -o build/hello
```

The bootstrap command uses official Dart once to build the seed. Subsequent stages compile the compiler's Dart sources with native `dartc`, compare repeated builds, and run a program against official Dart's behavior.

The native compiler uses `lib/src/runtime.dart` as its standard-runtime source. When placing the compiler outside the repository, supply its location:

```sh
dartc program.dart -o program --std /path/to/dartc/lib/src/runtime.dart
```

The compiler writes ARM64 instructions and Mach-O files directly. Local signing uses macOS `codesign`; no C compiler, assembler, or linker is required.

## Verify program behavior

```sh
dart run test/behavior_test.dart
```

The compiler architecture is described in [docs/architecture.md](docs/architecture.md).

MIT licensed.
