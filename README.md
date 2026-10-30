# dartc

A native Dart compiler written in Dart.

Compile Dart programs into standalone executables for macOS and Linux. Generated programs run without an installed Dart SDK.

dartc is an early preview. Complete Dart language and standard-library compatibility is the goal; see [language support](specs/README.md) for current capabilities and gaps. Published releases may differ from the source tree.

## Installation

### Native compiler

Download the archive for your platform from [GitHub Releases](https://github.com/medz/dartc/releases). Extract it, keep its contents together, and add its `bin` directory to your `PATH`.

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

Use `dartc --help` for command options. More examples are in [example/](example/).

## Native libraries

dartc can also produce object files, static libraries and shared libraries with C/C++ headers. See [export support](specs/types.md#ffi-类型与原生导出声明) for supported declarations and types.

## Development

Development requires Dart SDK `^3.13.7`.

```sh
git clone https://github.com/medz/dartc.git
cd dartc
dart pub get
```

Bug reports, feature requests and contributions are welcome through [GitHub Issues](https://github.com/medz/dartc/issues). When reporting a compiler problem, include the source program, dartc release or commit, target platform and expected behavior.

See [CHANGELOG.md](CHANGELOG.md) for release changes.

## License

[MIT](LICENSE).
