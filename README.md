# dartc

A native Dart compiler written in Dart.

The development version uses the official Dart analyzer and provides reusable analysis, IR and native code generation APIs. Its native backend builds integer, double and pointer functions as object files, static libraries and shared libraries. See the [language support tracker](https://github.com/medz/dartc/blob/main/specs/README.md) for supported behavior and remaining gaps.

Use `package:dartc/frontend.dart` to check libraries and translate them to IR, and `package:dartc/ir.dart` to inspect or construct verified SSA functions. Backend APIs are available separately through `target.dart`, `assembler.dart`, `assembler/arm64.dart`, `assembler/x64.dart`, `abi.dart`, `codegen.dart`, `object.dart`, `object/elf.dart`, `object/mach_o.dart` and `linker.dart`.

Compile `@Native<T>` calls with `Compiler.compile(nativeSymbols: ...)`, mapping each asset ID and requested symbol to a link symbol. Supply native objects, archives or explicit shared-library dependencies through `linkInputs` for shared output; object and archive outputs retain imports for later linking. The standalone `CodeGenerator.generate(imports: ...)` API accepts resolved `NativeImport` bindings, and `NativeCall` invokes typed function pointers through IR. Automatic asset discovery and runtime resolver fallback remain unimplemented.

Object and linker APIs support code, read-only data, writable data and zero-initialized storage, with cross-module calls and address references. `ObjectFormat.decodeObject(bytes)` reads supported Mach-O/ELF objects; `Archive.decode(bytes)` reads indexed static archives. Pass ordered `LinkInput.object(module)` and `LinkInput.archive(archive)` values to `Linker.linkSharedLibrary` to include objects and select the archive members needed by unresolved references. Dart global variables are not yet compiled to this storage.

Use `LinkInput.sharedLibrary(name, symbols: {localName: nativeName})` to call functions or reference data and function addresses in a separate library. Both symbol names include platform decoration; the dependency name is interpreted by the target loader. Mach-O binds to the named library, while ELF follows global symbol lookup. Required libraries and symbols must be available when loading the output. Address imports use `Relocation(indirect: true)` with ARM64 ADRP/LDR or x86-64 RIP-relative MOV; the loaded pointer refers to the actual definition.

`package:dartc/compiler.dart` combines these APIs. `Compiler.compile` accepts an `Output.object()`, `Output.staticLibrary()` or `Output.sharedLibrary(name)` request and returns a `Compilation` with final bytes and C declarations. `Compilation.write` saves them; it does not change the compiled library name.

For the previous compiler's broader native support, download [dartc 0.5.0](https://github.com/medz/dartc/releases/tag/v0.5.0). Its [usage guide](https://github.com/medz/dartc/blob/v0.5.0/README.md) applies to those release binaries.

## Native libraries

Mark a top-level function with an explicit FFI signature:

```dart
import 'dart:ffi';
import 'package:dartc/interop.dart';

@Export<Int64 Function(Int64, Int64)>(symbol: 'math_add')
int add(int left, int right) => left + right;
```

Save it as `math.dart` in a package that depends on this checkout, then build an object and its C/C++ header:

```sh
dart run dartc math.dart -o build/math.o --header build/math.h
```

Use `--kind static` or `--kind shared` for a library. Code generation, linking, static archives and Mach-O ad-hoc signing are implemented in Dart. Building libraries requires no external native toolchain. `--target` selects `macos-arm64`, `macos-x64`, `linux-arm64` or `linux-x64` independently of the host.

Native bodies support integer constants, addition, subtraction, multiplication, bitwise operations, comparisons, boolean expressions, branches, loops and direct calls. Exported signatures accept signed and unsigned 8-, 16-, 32- and 64-bit FFI integers, `Float`, `Double`, pointers to supported native types and `Void` results. Function pointers retain their complete nested signatures in parameters, results and generated headers; they can be passed between functions and constructed from addresses. Calling them through `asFunction` in compiled Dart remains unimplemented. Native boundaries convert integer widths and float precision; Dart calls between functions retain full `int` and `double` values, including calls to annotated functions. Functions can call helpers in other Dart libraries and recurse; values survive branches, loop iterations and calls. Calls between Dart functions also support boolean values, optional and named parameters, and constant defaults.

For independent tooling, `NativeSignature(Int64, [Int8])` accepts FFI type literals. `NativeSignature.types(result, parameters)` accepts `NativeTypeRef` descriptions for nested pointers, including `NativePointerType(NativeFunctionType(signature))`. The signature's `result` and `parameters` expose these descriptions; `NativeScalarType.type` gives the original scalar type literal.

Non-captured scalar locals can be assigned after declaration, including through branches and loops. Their values survive calls. Native `late` storage, nullable values and captured variables remain unimplemented.

Double operations include constants, negation, addition, subtraction, multiplication, IEEE division and comparisons, preserving NaN and signed-zero behavior. Mixed `int`/`double` arithmetic, exact comparisons, integer `/` and `toDouble` are supported for statically known numeric representations. Mixed parameter lists use both integer and floating-point registers, with excess arguments on the stack. Integer truncating division, remainder, shifts and other numeric conversions remain unsupported. Some mixed numeric constant expressions also remain unsupported; see the [numeric comparison limits](https://github.com/medz/dartc/blob/main/specs/expressions.md#数值比较与-sdk-差异).

Pointers to supported scalar types can use `Pointer<T>.fromAddress`, `.address`, equality, element offsets with `+` and `-`, and `.value` or indexed reads and writes, including compound assignments. Integer writes truncate to the element width; reads sign-extend or zero-extend according to the element type. `Pointer<Float>` stores 32-bit precision and widens reads to Dart `double`; `Pointer<Double>` uses 64-bit storage. A write does not narrow the original Dart variable or assignment expression's value. Callers own the native storage and must keep it alive and naturally aligned for access; indices are not bounds-checked. Pointer casts, other native element types, structs and callbacks remain unimplemented. General Dart executables, managed objects, exceptions and the complete target runtime also remain unimplemented in this checkout.

## SDK sources

Standard library sources must currently report version `3.13.7`. `--sdk` accepts an SDK directory, a Dart executable path or a command on `PATH`, such as `--sdk dart`. Dart command wrappers are queried for the SDK they actually launch. An invalid explicit source fails without falling back.

Without `--sdk`, dartc checks the SDK running the process, then Dart commands on `PATH`. If neither provides compatible sources, it downloads the [pinned official source revision](https://github.com/dart-lang/sdk/tree/416e33b0ffaef062a60ec966bb8c82ed2b83f128/sdk/lib) and caches its standard libraries and license. It downloads no SDK executable. Cache contents are verified before use; an interrupted download never becomes a usable cache. A damaged cache fails and must be removed explicitly before downloading again. User-code errors never trigger SDK reselection.

The default cache is `~/Library/Caches/dartc/sdk` on macOS and `~/.cache/dartc/sdk` on Linux; an absolute `XDG_CACHE_HOME` overrides the base directory. A complete cache works offline. Through `package:dartc/sdk.dart`, use `SdkResolver().resolve()` to select sources, or `SdkResolver().resolveCached()` to prepare the pinned sources before going offline. Both return a `DartSdk` accepted by `AnalysisSession` and `Compiler`. `SdkResolver(cacheDirectory: Directory(path))` selects a cache location. Caller-supplied SDK directories are checked for required files and version; their contents are not authenticated against the pinned source tree.

## Development

Use Dart SDK `^3.13.7` and run:

```sh
dart pub get
dart analyze --fatal-infos
dart test -P unit
dart run tool/print_ir.dart test/frontend/lowering/fixtures/functions.dart
```

The last command prints the basic blocks, calls and branches for each function in the file's library.

Assertions are disabled by default. Pass `enableAssertions: true` to the `Lowering` constructor to preserve assertion statements and constructor assertion initializers.

Run changed-domain tests during development. For native execution, build the host's assets (for example, `dart run tool/build_test_assets.dart macos-arm64`) and run `dart test -P native`. The unfiltered `dart test` runs all suites and requires assets for every target, built by omitting the target argument. See the [testing guide](test/README.md) for validation scope and cross-platform execution. Tests require no external native toolchain.

[Release notes](https://github.com/medz/dartc/blob/main/CHANGELOG.md) · [MIT license](https://github.com/medz/dartc/blob/main/LICENSE)
