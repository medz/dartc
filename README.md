# dartc

A native Dart compiler written in Dart.

The development version uses the official Dart analyzer and provides reusable analysis, IR and native code generation APIs. Its native backend builds integer functions as object files, static libraries and shared libraries. See the [language support tracker](https://github.com/medz/dartc/blob/main/specs/README.md) for supported behavior and remaining gaps.

Use `package:dartc/analyzer.dart` to check libraries, `package:dartc/lowering.dart` to translate them, and `package:dartc/ir.dart` to inspect or construct verified SSA functions. Backend APIs are available separately through `target.dart`, `arm64.dart`, `x64.dart`, `abi.dart`, `codegen.dart`, `artifact.dart`, `formats.dart` and `linker.dart`.

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

Use `--kind static` or `--kind shared` for a library. Linking uses the host's `ar` or `cc`; object encoding is implemented in Dart. `--target` selects `macos-arm64`, `macos-x64`, `linux-arm64` or `linux-x64` for object output. Library linking currently requires a matching host. `--sdk <root>` selects an installed SDK explicitly.

Native bodies currently support integer constants, addition, subtraction and returns, with register-passed `Int64` arguments and results. Unsupported operations and register pressure are reported as errors. General Dart executables, managed objects, exceptions and a target runtime remain unimplemented in this checkout.

## Development

Use Dart SDK `^3.13.7` and run:

```sh
dart pub get
dart analyze --fatal-infos
dart test
dart run tool/print_ir.dart test/lowering/fixtures/functions.dart
```

The last command prints the basic blocks, calls and branches for each function in the file's library.

Assertions are disabled by default. Pass `enableAssertions: true` to `Lowering.lower` to preserve assertion statements and constructor assertion initializers.

The native integration tests use the platform C/C++ compiler and archiver. Test inputs live in `test/compiler/fixtures/`; generated files are confined to `build/`.

[Release notes](https://github.com/medz/dartc/blob/main/CHANGELOG.md) · [MIT license](https://github.com/medz/dartc/blob/main/LICENSE)
