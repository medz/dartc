# dartc

A native Dart compiler written entirely in Dart.

`dartc` compiles Dart source directly to native machine code for macOS ARM64 and Linux ARM64/x86-64, and can rebuild its own compiler. The goal is a complete, independent Dart toolchain whose compiler, runtime and standard libraries can evolve in Dart. Version 0.4 is an early preview.

Generated executables include the reachable parts of dartc's own runtime, compiled to native code. Native compiler binaries and generated executables run without the official Dart SDK, VM, JIT or snapshots.

## Try the native compiler

Download the archive for your platform from the [0.4.0 release](https://github.com/medz/dartc/releases/tag/v0.4.0):

| Platform | Archive |
| --- | --- |
| macOS ARM64 | `dartc-0.4.0-macos-arm64.tar.gz` |
| Linux ARM64 | `dartc-0.4.0-linux-arm64.tar.gz` |
| Linux x86-64 | `dartc-0.4.0-linux-x64.tar.gz` |

Save this as `hello.dart`:

```dart
void main() {
  print('Hello, world!');
}
```

Extract the archive, then compile `hello.dart`. On macOS ARM64:

```sh
tar -xzf dartc-0.4.0-macos-arm64.tar.gz
export PATH="$PWD/dartc-0.4.0-macos-arm64/bin:$PATH"
dartc hello.dart -o hello
./hello
```

On Linux, use the same commands with `linux-arm64` or `linux-x64` in place of `macos-arm64`.

Keep the archive's `bin/` and `lib/` directories together. Matching dartc runtime sources are included in `lib/` for compilation. `SHA256SUMS` contains the archive checksums.

Upgrading from 0.3 requires replacing the whole archive: the internal runtime ABI changed from 14 to 17. See the [0.4.0 upgrade notes](CHANGELOG.md#upgrading-from-03).

The pub package uses the Dart SDK as the compiler's host:

```sh
dart pub global activate dartc
dartc hello.dart -o hello
```

The capabilities below refer to this source revision. See [published versions](https://pub.dev/packages/dartc/versions) for older packages.

## Dart compatibility

The [specification tracker](specs/README.md) records the reference SDK, current behavior, remaining gaps and owning tests by upstream language clause. Complete Dart language compatibility is the target.

| Area | Implemented behavior |
| --- | --- |
| Values | Native integers and doubles, booleans, Unicode strings, nullable values, typed lists with conditional/loop/spread and null-aware elements and runtime type checks |
| Declarations | Local object/List destructuring declarations and assignments, pattern loop bindings, top-level variables, lazy initialization, classes with inheritance, abstract classes and interfaces, enums with fields, constructors and methods, instance/static fields and methods, bound method values, named/unnamed constructors with field initializer lists, getters, setters and generic type aliases |
| Functions | Generic top-level and method calls with bounds and partial inference, callable objects, recursion, local and anonymous functions with value/type captures, optional/named direct and function-value calls, constructor values and structural function types |
| Control flow | Blocks, assignments, cascades, null-aware member/index chains, conditions and if-case statements/elements, loops, labelled jumps, switch statements/expressions with scalar/object/list patterns and guards, shared case bodies and case-label continue, returns and synchronous exceptions |
| Libraries | Relative, file/package imports and exports, prefixes, filters, conditional URIs and library parts |
| Constants | Scalar/list constants, canonical const instances, metadata and supported core pragmas |
| Core APIs | print, command-line arguments, basic String/List operations and StringBuffer object/character writing |

Generic classes, dynamic member calls, mixins, extensions, records, map/record patterns, asynchronous code, isolates and most SDK libraries are not implemented, and enums have no type parameters or mixins. Exceptions are synchronous only. Generic function values, complete generic inference and generic or standard-library constructor tear-offs remain unsupported. Failed runtime checks terminate the process. Managed storage is retained until process exit.

Package configuration v2 supplies local package mappings and default language versions. A leading `// @dart = major.minor` comment can select an implemented versioned rule from 2.12 through 3.13; this is not complete compatibility with those language versions. See [libraries](specs/libraries.md) and [lexical structure](specs/lexical-structure.md).

## Packages and runtime sources

Run `dart pub get` to resolve dependencies. `dartc` discovers the nearest `.dart_tool/package_config.json` above the entry file, or accepts an explicit configuration:

```sh
dartc bin/main.dart --packages .dart_tool/package_config.json -o app
```

`dartc` reads local file-backed packages; it does not download packages or solve versions. Use consistent library URIs: package and file references to one physical file can identify different libraries.

To select runtime sources explicitly:

```sh
dartc main.dart --std /path/to/dartc/lib/src/runtime.dart -o app
```

Compiler and runtime sources must have matching ABIs. Keep them from the same release unless following the [bootstrap design](doc/architecture.md).

## Build from source

Development validation uses the installed Dart SDK on macOS ARM64 or Linux ARM64/x86-64. Differential and benchmark reports record the SDK version used.

```sh
git clone https://github.com/medz/dartc.git
cd dartc
dart pub get
dart tool/bootstrap.dart
build/dartc-stage2 example/hello.dart -o build/hello
./build/hello
```

Bootstrap starts with the verified local `build/dartc-seed`. Only when no local seed exists does it build an initial seed with official Dart. It checks repeated native builds and behavior before replacing the seed. An existing seed's failure does not fall back to official compilation.

An extracted native release can also serve as the seed:

```sh
dart tool/bootstrap.dart --seed /path/to/dartc-release/bin/dartc
```

The compiler, allocator, runtime algorithms, machine-code generation, executable formats and local Mach-O signatures are implemented in Dart. No C compiler, assembler, linker or signing subprocess is needed to build executables.

## Other outputs

Choose the output target explicitly:

```sh
dartc hello.dart --target linux-arm64 -o hello-linux
dartc hello.dart --target linux-x64 -o hello-linux-x64
dartc hello.dart --target macos-arm64 -o hello-macos
```

Experimental macOS library output accepts an explicitly typed Pointer.fromFunction binding, as shown in [example/math.dart](example/math.dart):

```sh
dartc example/math.dart --emit dylib --export add -o libmath.dylib
dartc example/math.dart --emit static --export add -o libmath.a
```

`--emit object` produces a Mach-O object. This path supports `Int64` parameters and results, without allocation, global state or a Dart runtime context. Linux library output is not implemented.

## Contributing

Start language work from the [specification tracker](specs/README.md). See the [architecture](doc/architecture.md) for compiler/runtime design, [runtime contracts](doc/runtime.md) for memory and ownership rules, and [developer tooling](doc/development.md) for compiler/program benchmarks and differential testing.
