<div align="center">

# dartc

### Dart in. Native code out.

A native Dart compiler written in Dart.<br>
Build standalone programs and C-compatible libraries.

[Get started](#get-started) · [Examples](#your-first-program) · [Platforms](#supported-platforms) · [Documentation](#documentation)

</div>

---

## Write Dart. Build native.

Turn supported Dart code into a program you can distribute or a library another application can call.

| Build a program | Export a function | Choose an output |
| --- | --- | --- |
| Produce a standalone executable. | Expose a C-compatible interface with a generated C/C++ header. | Create executables, object files, static libraries or shared libraries. |

The compiler, assembler and linker are implemented in Dart. Building native outputs does not require a separate C compiler or linker.

Most of the language and of the core libraries work; [what does not](#know-what-to-expect) is listed below. A program that uses something unsupported does not compile: dartc reports where it is.

## Get started

### Install dartc

Download the compiler for your machine from [Releases](https://github.com/medz/dartc/releases/latest).

1. Extract the archive.
2. Add its `bin` directory to your `PATH`, or move `bin/dartc` to a directory already on your `PATH`.
3. Check the installation:

```sh
dartc --help
```

The native compiler is self-contained. Neither it nor the executables it produces require an installed Dart SDK. Project dependencies must already be available locally; dartc does not download packages for you.

## Your first program

Choose a standalone program or a function you can use from native code.

[Executable](#example-executable) · [Native library](#example-native-library)

<a name="example-executable"></a>

<details open>
<summary><strong>Executable · Compile and run a program</strong></summary>

Save this as `hello.dart`:

```dart
void main(List<String> names) {
  print('Hello ${names.isEmpty ? 'world' : names.join(', ')}!');
}
```

Compile and run it:

```sh
dartc hello.dart -o hello
./hello Ada Grace
```

```text
Hello Ada, Grace!
```

For a Dart project, resolve its dependencies before compiling the entry point:

```sh
dart pub get
dartc bin/main.dart -o app
```

Assertions are disabled by default. Use `--enable-asserts` to check those outside the standard libraries.

Entry points can be synchronous or async, with optional command-line arguments. Normal completion uses `dart:io`'s `exitCode` after pending events finish, defaulting to zero; the Dart return value is discarded. `exit(code)` terminates immediately, while `sleep(duration)` blocks event delivery for the requested duration.

Pass compilation declarations for `String.fromEnvironment`, `int.fromEnvironment`, `bool.fromEnvironment` and `bool.hasEnvironment`:

```sh
dartc bin/main.dart -o app -DAPP_NAME=demo --define DEBUG=false
```

Declarations also select conditional imports and exports. They are separate from the program's OS environment. The compiler itself supplies `dart.library.*` and `dart.vm.product`; callers cannot override them.

</details>

<a name="example-native-library"></a>

<details>
<summary><strong>Native library · Export and call a function</strong></summary>

In a Dart package, add dartc as a dependency:

```sh
dart pub add dartc
```

Save this as `math.dart`:

```dart
import 'dart:ffi';
import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64, Int64)>(symbol: 'math_add')
int add(int left, int right) => left + right;
```

`@Export` gives the function a native name and signature. Here, `math_add` takes two signed 64-bit integers and returns one.

Build a shared library and its C/C++ header.

On macOS:

```sh
dartc math.dart --kind shared \
  -o build/libmath.dylib --header build/math.h
```

On Linux:

```sh
dartc math.dart --kind shared \
  -o build/libmath.so --header build/math.h
```

You can load this library from a program with a compatible native calling interface. To try it using Dart FFI, create `call_math.dart`:

```dart
import 'dart:ffi';
import 'dart:io';

void main() {
  final path = Platform.isMacOS
      ? 'build/libmath.dylib'
      : 'build/libmath.so';

  final library = DynamicLibrary.open(File(path).absolute.path);
  final add = library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'math_add',
      );

  print(add(20, 22));
  library.close();
}
```

Run this caller with the Dart SDK:

```sh
dart run call_math.dart
```

```text
42
```

The caller uses the Dart SDK; the addition runs in the library compiled by dartc.

</details>

## Fit your build

An executable is ready to run. Libraries let you bring compiled Dart functions into another application.

| Output | Use it when… | Command |
| --- | --- | --- |
| Object file | Another build system will link the code. | `dartc math.dart --kind object -o math.o` |
| Static library | You want an archive for native linking. | `dartc math.dart --kind static -o libmath.a` |
| Shared library | Another program will load the code at runtime. | `dartc math.dart --kind shared -o libmath.dylib` |

Use `.so` for shared-library filenames on Linux. Add `--header math.h` to generate C/C++ declarations for the exported functions.

Functions exported by name are top-level, synchronous and not generic, and have required positional parameters. They take and give what `dart:ffi` functions do: integers, `Float`, `Double`, `Bool`, pointers, structs and unions.

## Supported platforms

| Operating system | CPU architecture | Target |
| --- | --- | --- |
| macOS | Apple Silicon / ARM64 | `macos-arm64` |
| Linux, glibc 2.34 or later | ARM64 | `linux-arm64` |
| Linux, glibc 2.34 or later | x86-64 | `linux-x64` |

The default target matches the host. Select another platform with `--target`:

```sh
dartc math.dart --kind shared \
  --target linux-arm64 -o build/libmath.so
```

Cross-compilation does not require a matching host. Running or loading the result requires the selected target environment.

## Know what to expect

Programs are compared with the official Dart SDK, whose behavior is what dartc aims at. Programs typically take 1 to 3.5 times as long as those that the official AOT compiler makes.

Not supported yet:

- `dart:isolate`, and of `dart:io` the network, subprocesses, signals, compression and watching files.
- Deferred imports, variables of type `Never`, `external` variables, operations on SIMD values.
- Stack traces have no text.
- `Expando`, `WeakReference` and `Finalizer` keep objects alive. Native finalizers run when the program ends.
- `\p{…}` in regular expressions throws when used.

JavaScript interop and `dart:mirrors` are out of scope.

<details>
<summary><strong>Command reference</strong></summary>

```sh
dartc <source.dart> -o <output> [options]
```

| Option | Purpose |
| --- | --- |
| `-o <path>` | Set the required output path. |
| `--kind <kind>` | Select `exe`, `object`, `static` or `shared`. Defaults to `exe`. |
| `--header <path>` | Write C/C++ declarations for native exports. |
| `-D<name>=<value>` | Declare a value for `fromEnvironment`. Also `--define`. |
| `--enable-asserts` | Check assertions. |
| `--target <target>` | Select an output platform. Defaults to the host. |

The exit code is 0 if the output was written, 1 if the program cannot be compiled, and 64 if the command is wrong.

</details>

## Documentation

- [Compiler API](lib/compiler.dart): compile from Dart.
- [Architecture](ARCHITECTURE.md) and [plan](PLAN.md), in Chinese: how the compiler works, and what is next.
- [Testing guide](test/README.md).
- [SDK sources](sdk/README.md).

## Contributing

A small reproducer is one of the most useful contributions you can make.

When [reporting a compiler issue](https://github.com/medz/dartc/issues), include the source, compiler release or commit, target platform, command and expected result.

With Dart SDK 3.14.0:

```sh
dart analyze --fatal-infos
dart test
dart run bin/dartc.dart hello.dart -o hello
```

Build the compiler as one program that needs no other files:

```sh
dart run tool/build.dart
./build/dartc --help
```

---

<div align="center">

[Releases](https://github.com/medz/dartc/releases/latest) · [Release notes](CHANGELOG.md) · [GitHub Issues](https://github.com/medz/dartc/issues) · [MIT license](LICENSE)

</div>
