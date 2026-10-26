# dartc

A native Dart compiler written in Dart.

`dartc` is experimental. The first release compiles a small Dart subset to standalone macOS ARM64 executables: `main()` and `print()` with string literals. Generated programs do not require the Dart VM. Full Dart language and standard-library compatibility are not yet supported.

## Install

Requires Dart 3.13 or later and macOS on Apple Silicon.

```sh
dart pub global activate dartc
```

## Compile

Create `hello.dart`:

```dart
void main() {
  print('Hello, world!');
}
```

Compile and run:

```sh
dartc hello.dart -o hello
./hello
```

The compiler writes ARM64 instructions and Mach-O files directly. It uses macOS `codesign` for local signing; no C compiler, assembler, or linker is required.

MIT licensed.
