# dartc

A native Dart compiler written in Dart.

The goal is for Dart to bootstrap and evolve its own compiler, runtime and standard libraries through an independent, optimizing native toolchain.

Version 0.2 is an early preview. `dartc` compiles Dart source directly to ARM64 machine code for macOS and Linux. Native compiler binaries and generated executables run without the Dart SDK, VM or snapshots.

## Try the native compiler

Download the archive for your platform from the [0.2.0 release](https://github.com/medz/dartc/releases/tag/v0.2.0):

- `dartc-0.2.0-macos-arm64.tar.gz`
- `dartc-0.2.0-linux-arm64.tar.gz`

For example, on macOS ARM64:

```sh
tar -xzf dartc-0.2.0-macos-arm64.tar.gz
export PATH="$PWD/dartc-0.2.0-macos-arm64/bin:$PATH"
dartc hello.dart -o hello
./hello
```

Keep the archive's `bin/` and `lib/` directories together. Compatible Dart runtime sources are included in `lib/`. `SHA256SUMS` contains the archive checksums.

The pub package uses the Dart SDK as the compiler's host:

```sh
dart pub global activate dartc
dartc hello.dart -o hello
```

The capabilities below refer to this source revision. See [published versions](https://pub.dev/packages/dartc/versions) for older packages.

## Dart compatibility

The compatibility baseline is Dart 3.13.5, with complete language implementation as the target. The [specification tracker](specs/README.md) records current behavior, remaining gaps and owning tests by upstream language clause.

| Area | Implemented behavior |
| --- | --- |
| Values | Native integers, booleans, Unicode strings, nullable values, typed lists and runtime type checks |
| Declarations | Top-level variables, lazy initialization, simple classes, fields, named/unnamed constructors with field initializer lists, getters and setters |
| Functions | Direct calls, recursion, local and anonymous functions without runtime captures, optional/named direct arguments, required-positional function values and structural function types |
| Control flow | Blocks, assignments, conditions, loops, labelled jumps, constant switch cases and returns |
| Libraries | Relative, file/package imports and exports, prefixes, filters, conditional URIs and library parts |
| Constants | Scalar/list constants, canonical const instances, metadata and supported core pragmas |
| Core APIs | print, command-line arguments, basic String/List operations and StringBuffer object/character writing |

Capturing closures, inheritance, general generics and dynamic member calls, mixins, extensions, records, patterns, exceptions, async code, isolates and most SDK libraries are not implemented. General optional/named function-value signatures and method/constructor tear-offs remain unsupported. Failed runtime checks terminate the process. Managed storage is retained until process exit.

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

Development validation uses Dart 3.13.5 on macOS/Linux ARM64.

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

Choose a different ARM64 target explicitly:

```sh
dartc hello.dart --target linux-arm64 -o hello-linux
dartc hello.dart --target macos-arm64 -o hello-macos
```

Experimental macOS library output accepts an explicitly typed Pointer.fromFunction binding, as shown in [example/math.dart](example/math.dart):

```sh
dartc example/math.dart --emit dylib --export add -o libmath.dylib
dartc example/math.dart --emit static --export add -o libmath.a
```

`--emit object` produces a Mach-O object. This path supports `Int64` parameters and results, without allocation, global state or a Dart runtime context. Linux library output is not implemented.

## Contributing

Start language work from [specs](specs/README.md). Compiler/runtime design is in [architecture.md](doc/architecture.md), and runtime contributor contracts are in [runtime.md](doc/runtime.md).

Compare existing native engines on the same compiler task with `dart tool/benchmark.dart --compare <baseline> <candidate>`. Running the benchmark without that option builds a separate official AOT reference. Reference binaries never become bootstrap seeds. Development CI is manually dispatched.

The report records elapsed time, user/system CPU time and kernel peak RSS on macOS/Linux ARM64, using a fresh sampling process for each task. Sampling driver startup and bookkeeping are excluded; unavailable metrics remain null. Comparison requires unchanged inputs and identical generated bytes. Peak RSS is the maximum child high-water mark, rather than total concurrent process memory. Code generation changes need separate behavior and performance comparisons.

Run `dart tool/fuzz.dart --seed 1 --count 20` for bounded integer/boolean differential cases. Each case compares the SDK oracle, SDK-hosted dartc and native dartc. Failures retain actual sources, dependencies, commands and a frozen compiler/runtime/tool snapshot under `build/fuzz/`; the printed replay command uses those files. Generated cases support `--replay <saved case> --shrink`. Use `--case <saved case>` with a repaired compiler to verify a fix, and `--help` for explicit rejection and runtime-failure contracts.
