# dartc

A native Dart compiler written in Dart.

Compile Dart programs into standalone executables for macOS and Linux. Generated programs run without an installed Dart SDK.

dartc is an early preview. Complete Dart language and standard-library compatibility is the goal; see [language support](https://github.com/medz/dartc/blob/main/specs/README.md) for current capabilities and gaps. Published releases may differ from the source tree.

## Installation

### Native compiler

Download the archive for your platform from [GitHub Releases](https://github.com/medz/dartc/releases). Extract it and add its `bin` directory to your `PATH`.

See the release notes for available platforms, checksums and upgrade instructions.

### Dart package

With the [Dart SDK](https://dart.dev/get-dart) installed:

```sh
dart pub global activate dartc
```

## Quick start

Save this as `hello.dart`:

```dart
void main() {
  print('Hello, world!');
}
```

Compile and run it:

```sh
dartc hello.dart -o hello
./hello
```

For a Dart project, resolve its dependencies before compiling the entry point:

```sh
dart pub get
dartc bin/main.dart -o app
```

Use `dartc --help` for command options. More examples are in [example/](https://github.com/medz/dartc/tree/main/example).

## Native libraries

dartc can also produce object files, static libraries and shared libraries with C/C++ headers. See [export support](https://github.com/medz/dartc/blob/main/specs/types.md#ffi-类型与原生导出声明) for supported declarations and types.

## Package APIs

Use these libraries independently in a Dart application:

| Library | Purpose | Example |
| --- | --- | --- |
| `package:dartc/source.dart` | Source text, UTF-16 ranges, and line and column lookup | [Source locations](https://github.com/medz/dartc/blob/main/example/source.dart) |
| `package:dartc/diagnostics.dart` | Diagnostics with severity, source ranges, and related notes | [Diagnostics](https://github.com/medz/dartc/blob/main/example/diagnostics.dart) |
| `package:dartc/scanner.dart` | Dart tokens, comments, and lexical errors | [Scanning](https://github.com/medz/dartc/blob/main/example/scanner.dart) |
| `package:dartc/ast.dart` | Compilation units, directives, declarations, types, expressions, statements, and patterns | [Inspecting syntax](https://github.com/medz/dartc/blob/main/example/ast.dart) |
| `package:dartc/parser.dart` | Compilation units, declarations, expressions, statements and types with syntax diagnostics | [Parsing syntax](https://github.com/medz/dartc/blob/main/example/parser.dart) |

These APIs are available from the source repository and have not been released yet.

## Development

Development requires Dart SDK `^3.13.7`.

```sh
git clone https://github.com/medz/dartc.git
cd dartc
dart pub get
```

Bug reports, feature requests and contributions are welcome through [GitHub Issues](https://github.com/medz/dartc/issues). When reporting a compiler problem, include the source program, dartc release or commit, target platform and expected behavior.

See [CHANGELOG.md](https://github.com/medz/dartc/blob/main/CHANGELOG.md) for release changes.

## License

[MIT](https://github.com/medz/dartc/blob/main/LICENSE).
