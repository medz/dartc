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

Dart language and standard-library coverage is incomplete. Check the [language support guide](specs/README.md) before bringing an existing application.

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
<summary><strong>Executable · Compile and check a calculation</strong></summary>

Save this as `sum.dart`:

```dart
int sum(int limit) {
  var result = 0;
  for (var i = 1; i <= limit; i++) {
    result += i;
  }
  return result;
}

void main() {
  if (sum(10) != 55) throw 1;
}
```

Compile and run it:

```sh
dartc sum.dart --kind exe -o sum
./sum && echo "Sum check passed"
```

```text
Sum check passed
```

The executable adds the integers from 1 to 10 and checks the result. It exits successfully when the check passes; the shell prints the confirmation. The program itself does not write to stdout. Native `print` calls are not supported yet.

For a Dart project, resolve its dependencies before compiling the entry point:

```sh
dart pub get
dartc bin/main.dart --kind exe -o app
```

Executable entry points must be synchronous and parameterless. Normal completion exits with status zero; the Dart return value is discarded.

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

## See what you ship

For the sum-check program above, the generated executables measured:

| Compiler | File size |
| --- | ---: |
| dartc | **33,360 bytes (32.58 KiB)** |
| Dart SDK `compile exe` | **5,731,232 bytes (5.47 MiB)** |

Both executables ran successfully with the same exit status and no stdout or stderr. These figures describe this small example, not an expected reduction for every application or a claim about execution speed.

<details>
<summary><strong>Measurement conditions</strong></summary>

- macOS 27.2 (26B123), ARM64.
- dartc source revision `b12319a107c82d553a1e7d7901b70226142bd1bc`, run using the Dart SDK; Dart SDK 3.13.7 stable for the comparison.
- Identical `sum.dart` source from the example above, with default compiler settings.
- Uncompressed executable file bytes, including generated ad-hoc signatures. No additional stripping, compression or signing.
- Both outputs depend on system libraries. The SDK output supports a broader runtime; this is not a comparison of complete language compatibility or total system dependency size.

The output selections were equivalent to:

```sh
dartc sum.dart --kind exe -o sum-dartc
dart compile exe sum.dart -o sum-sdk
```

For the measurement, dartc was invoked as `dart --packages=<package_config.json> bin/dartc.dart`, using an isolated copy of the compiler sources. Rebuilding from that copy produced a byte-identical program executable.

</details>

## Fit your build

An executable is ready to run. Libraries let you bring compiled Dart functions into another application.

| Output | Use it when… | Command |
| --- | --- | --- |
| Object file | Another build system will link the code. | `dartc math.dart --kind object -o math.o` |
| Static library | You want an archive for native linking. | `dartc math.dart --kind static -o libmath.a` |
| Shared library | Another program will load the code at runtime. | `dartc math.dart --kind shared -o libmath.dylib` |

Use `.so` for shared-library filenames on Linux. Add `--header math.h` to generate C/C++ declarations for the exported functions.

Native exports accept fixed-width FFI integers, `IntPtr`/`UintPtr`, `Bool`, `Float`/`Double`, typed pointers, structs and unions passed by value, and `Void` results. See the [native library guide](specs/libraries.md#原生库) for supported signatures and function bodies.

## Supported platforms

| Operating system | CPU architecture | Target |
| --- | --- | --- |
| macOS | Apple Silicon / ARM64 | `macos-arm64` |
| macOS | Intel / x86-64 | `macos-x64` |
| Linux | ARM64 | `linux-arm64` |
| Linux | x86-64 | `linux-x64` |

The default target matches the host. Select another platform with `--target`:

```sh
dartc math.dart --kind shared \
  --target linux-arm64 -o build/libmath.so
```

Cross-compilation does not require a matching host. Running or loading the result requires the selected target environment.

Linux executables currently use fixed addresses and statically resolved inputs. Dynamic executable linking and position-independent executables are not supported.

## Know what to expect

Numerical functions, direct calls, branches, loops and native scalar pointer access are useful starting points.

Object construction, nullable values, type checks and synchronous exceptions have native implementations within a limited scope. Full class dispatch, asynchronous execution and complete standard-library support remain incomplete.

The [compatibility guide](specs/README.md) distinguishes source analysis, IR behavior and native execution. A construct accepted by analysis is not necessarily executable.

<details>
<summary><strong>Command reference</strong></summary>

```sh
dartc <source.dart> -o <output> [options]
```

| Option | Purpose |
| --- | --- |
| `-o <path>` | Set the required output path. |
| `--kind <kind>` | Select `object`, `static`, `shared` or `exe`. Defaults to `object`. |
| `--header <path>` | Write C/C++ declarations for native exports. |
| `--target <target>` | Select an output platform. Defaults to the host. |

Use `dartc --help` to display command syntax.

</details>

## Documentation

- [Language support](specs/README.md): supported behavior and compatibility gaps.
- [Native libraries](specs/libraries.md#原生库): exports, FFI types and linking.
- [Compiler API](lib/compiler.dart): compile programmatically and retrieve generated bytes and headers.
- [Testing guide](test/README.md): prepare assets and run relevant checks.

## Contributing

A small reproducer is one of the most useful contributions you can make.

When [reporting a compiler issue](https://github.com/medz/dartc/issues), include the source, compiler release or commit, target platform, command and expected result.

For code contributions, start with the compatibility and testing guides:

```sh
dart analyze --fatal-infos
dart test -P unit
```

Native tests require prepared assets; follow the testing guide for the relevant platform and feature.

Build a standalone development compiler with Dart SDK 3.14.0:

```sh
dart run tool/build.dart
./build/dartc --help
```

The build includes the package's fixed source resources. To regenerate those resources from the pinned official SDK sources, run `dart run tool/build_sources.dart`; only this resource preparation step may download the fixed source revision.

---

<div align="center">

[Releases](https://github.com/medz/dartc/releases/latest) · [Release notes](CHANGELOG.md) · [GitHub Issues](https://github.com/medz/dartc/issues) · [MIT license](LICENSE)

</div>
