# dartc

A native Dart compiler written in Dart.

The development version uses the official Dart analyzer and lowers checked libraries to a typed intermediate representation. See the [language support tracker](https://github.com/medz/dartc/blob/main/specs/README.md) for the constructs you can try today.

Use `package:dartc/lowering.dart` to produce an `IrProgram` with class declarations and function bodies. Use `package:dartc/ir.dart` to inspect the program or build and verify SSA functions.

For a working native compiler, download [dartc 0.5.0](https://github.com/medz/dartc/releases/tag/v0.5.0). Its [usage guide](https://github.com/medz/dartc/blob/v0.5.0/README.md) applies to the release binaries.

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

[Release notes](https://github.com/medz/dartc/blob/main/CHANGELOG.md) · [MIT license](https://github.com/medz/dartc/blob/main/LICENSE)
