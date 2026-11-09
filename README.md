# dartc

A native Dart compiler written in Dart.

The development version uses the official Dart analyzer and provides reusable analysis, IR and native code generation APIs. Its native backend builds integer functions as object files, static libraries and shared libraries. See the [language support tracker](https://github.com/medz/dartc/blob/main/specs/README.md) for supported behavior and remaining gaps.

Use `package:dartc/frontend.dart` to check libraries and translate them to IR, and `package:dartc/ir.dart` to inspect or construct verified SSA functions. Backend APIs are available separately through `target.dart`, `assembler.dart`, `assembler/arm64.dart`, `assembler/x64.dart`, `abi.dart`, `codegen.dart`, `object.dart`, `object/elf.dart`, `object/mach_o.dart` and `linker.dart`.

Object and linker APIs support code, read-only data, writable data and zero-initialized storage, with cross-module calls and address references. `ObjectFormat.decodeObject(bytes)` reads supported Mach-O/ELF objects; `Archive.decode(bytes)` reads indexed static archives. Pass ordered `LinkInput.object(module)` and `LinkInput.archive(archive)` values to `Linker.linkSharedLibrary` to include objects and select the archive members needed by unresolved references. Dart global variables are not yet compiled to this storage.

`package:dartc/compiler.dart` combines these APIs. `Compiler.compile` accepts an `Output.object()`, `Output.staticLibrary()` or `Output.sharedLibrary(name)` request and returns a `Compilation` with final bytes and C declarations. `Compilation.write` saves them; it does not change the compiled library name.

For the previous compiler's broader native support, download [dartc 0.5.0](https://github.com/medz/dartc/releases/tag/v0.5.0). Its [usage guide](https://github.com/medz/dartc/blob/v0.5.0/README.md) applies to those release binaries.

## Native libraries

Mark a top-level function with an explicit FFI signature:

```dart
import 'dart:ffi';
import 'package:dartc/export.dart';

@Export<Int64 Function(Int64, Int64)>(symbol: 'math_add')
int add(int left, int right) => left + right;
```

Save it as `math.dart` in a package that depends on this checkout, then build an object and its C/C++ header:

```sh
dart run dartc math.dart -o build/math.o --header build/math.h
```

Use `--kind static` or `--kind shared` for a library. Code generation, linking, static archives and Mach-O ad-hoc signing are implemented in Dart. Building libraries requires no external native toolchain. `--target` selects `macos-arm64`, `macos-x64`, `linux-arm64` or `linux-x64` independently of the host. `--sdk <root>` selects an installed SDK explicitly.

Native bodies support integer constants, addition, subtraction, multiplication, bitwise operations, comparisons, boolean expressions, branches, loops and direct calls, with `Int64` arguments passed in registers and on the stack and an `Int64` result. Functions can call helpers in other Dart libraries and recurse; values survive branches, loop iterations and calls. Boolean parameters and results are supported between Dart functions, while exported signatures remain `Int64`. Division, remainder, shifts and other unsupported operations and signatures are reported as errors. General Dart executables, managed objects, exceptions and a target runtime remain unimplemented in this checkout.

## Development

Use Dart SDK `^3.13.7` and run:

```sh
dart pub get
dart analyze --fatal-infos
dart run tool/build_test_assets.dart && dart test
dart run tool/print_ir.dart test/frontend/lowering/fixtures/functions.dart
```

The last command prints the basic blocks, calls and branches for each function in the file's library.

Assertions are disabled by default. Pass `enableAssertions: true` to the `Lowering` constructor to preserve assertion statements and constructor assertion initializers.

Before running tests, build the fixed native assets with `dart run tool/build_test_assets.dart`. Sources and Dart FFI bindings live in each domain's `test/<domain>/fixtures/` directory; generated files go to `build/test/<target>/`. Native execution tests call these bindings directly. Rebuild the assets after changing the compiler or fixtures. Tests require no external native toolchain.

[Release notes](https://github.com/medz/dartc/blob/main/CHANGELOG.md) · [MIT license](https://github.com/medz/dartc/blob/main/LICENSE)
