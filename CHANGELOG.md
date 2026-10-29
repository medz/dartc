## Unreleased

### Performance

- Inline small, effect-free direct calls before machine lowering, allowing constant propagation across call boundaries while preserving argument evaluation and GC contracts.
- Reduce polymorphic method and property access overhead by reading the receiver's exact class identity once per dispatch, while preserving inherited implementations and target defaults.

## [0.4.0](https://github.com/medz/dartc/compare/v0.3.0...v0.4.0) — 2026-10-29

This release adds Linux x86-64 binaries and expands native Dart programs with
class hierarchies, enums, custom operators, doubles and synchronous exceptions.
It remains an early preview, with Dart SDK 3.13.7 as the behavior reference.

### Features

- **Platforms:** add Linux x86-64 executables and a native compiler archive alongside macOS ARM64 and Linux ARM64. All three targets can compile the compiler and generate executables for the other targets.
- **Classes:** support non-generic abstract classes, inheritance and interfaces, including inherited fields, implementation dispatch, `super` access and constructor chains.
- **Constructors:** add primary constructors, declaring parameters, `super` parameters, factories, const factories and factory redirection. Support constructor function values and contextual dot shorthands for supported constructors and static members.
- **Enums:** support simple and enhanced non-generic enums, with fields, constructors, methods, `values`, `index`, `name` and exhaustive switches.
- **Operators:** support user-defined binary and unary operators, `[]` and `[]=`, including subclass dispatch, compound assignment and increments. `operator ==` remains a language implementation gap.
- **Function values:** accept optional positional and named parameters, preserve target defaults and check structural function types. Non-generic closures inside generic functions can capture enclosing type arguments as well as values.
- **Numbers:** add native double literals, arithmetic, mixed numeric values, decimal parsing, shortest round-trip formatting, conversions and constants.
- **Exceptions:** support synchronous `throw`, `try`/`on`/`catch`/`finally` and `rethrow`, including cleanup during returns and jumps. Add `StackTrace.current`, `StackTrace.fromString` and `StackTrace.empty`.
- **Variables:** support lazy `late` locals, captured variables, top-level/static variables and typed instance fields, including final assignment and reentrant initialization checks.

### Fixes

- Integer division or modulo by zero on ARM64 now terminates before later side effects instead of producing a value. Runtime errors still cannot be caught as Dart exceptions.
- Indexed assignments preserve separate read/write index conversions, short-circuiting and evaluation order when user-defined operators participate.
- Non-returning calls remain non-returning in native code. Return inference and missing-return checks account for null-aware elements and empty `List<Never>` spreads.
- Setter and `[]=` return types accept aliases resolving to `void`; invalid return types are checked even in unused declarations. Constructor function signatures retain inferred field and super parameter types.

### Upgrading from 0.3

Replace the complete native archive, keeping its `bin/` and `lib/` directories
together. The runtime ABI changes from 14 to 17; compiler, runtime, layout and
standard-library files must come from the same release.

For a source build, use the 0.4.0 native compiler for your host as the bootstrap
seed. A 0.3 compiler does not understand all the syntax now used by dartc itself:

```sh
dart tool/bootstrap.dart --seed /path/to/dartc-0.4.0-macos-arm64/bin/dartc
```

The SDK-hosted package can be updated with `dart pub global activate dartc 0.4.0`.
Language implementation remains incomplete; detailed behavior and gaps are in
[specs](https://github.com/medz/dartc/tree/v0.4.0/specs).

## 0.3.0

Early preview release for macOS and Linux ARM64, with Dart SDK 3.13.7 as the behavior reference.

- Add lexical captures to local and anonymous functions, including shared writes, `this`, recursion and per-iteration loop bindings.
- Support bound instance-method values, callable objects and implicit `call` extraction in supported function contexts.
- Support generic top-level and method calls with bounds, partial contextual inference and runtime type arguments, including type-changing recursion; add generic aliases and traditional function typedefs.
- Support switch expressions, if-case, object/List patterns, destructuring declarations and assignments, pattern loops and pattern switch statements with guards and shared case bodies.
- Support cascades, null-aware member/index chains and List conditional, loop, spread and null-aware elements.
- Add static members, named and const constructors, field initializer lists, generative redirection, explicit `new` and constructor aliases.
- Implement `List.insert`, `List.removeAt`, `List.sublist`, `StringBuffer.writeCharCode` and `StringBuffer.isNotEmpty` in Dart.
- Update the native runtime ABI from 11 to 14 for captured values, bound methods and heap type metadata. Use the compiler and runtime sources from the same release.
- Verify SSA types, definitions, control flow and dominance before machine lowering; extend root enumeration to captured values and runtime type graphs.
- Add SDK/hosted/native differential generation with saved-case replay and reduction, compiler CPU/RSS sampling and program compilation/execution benchmarks that check behavior and output files.
- Reject stale artifacts and incomplete validation evidence; bootstrap keeps the existing verified seed when rebuilding or validation fails.

Language implementation remains incomplete. Current behavior and remaining gaps are tracked in [specs/](specs/README.md).

## 0.2.0

Early preview release for macOS and Linux ARM64.

- Provide standalone native compiler archives with compatible runtime sources.
- Support simple classes, accessors, nullable/reified value checks, canonical const instances and lazy top-level initialization.
- Add noncapturing local and anonymous functions, structural function types and nongeneric type aliases.
- Resolve package configuration v2, language versions, file/package URIs, conditional imports and library parts.
- Check runtime NoGC contracts and retain runtime components according to actual dependencies.

Captures, inheritance, general generics, exceptions, async code and most SDK libraries remain unsupported. Runtime sources and native compiler binaries from older releases must not be mixed with this version.

## 0.1.0

- Compile functions, control flow, strings, lists, and relative imports.
- Build a standalone native compiler that can compile its own Dart sources.
- Generate macOS and Linux ARM64 executables, including local Mach-O signatures in Dart.
- Export explicitly typed FFI callbacks as experimental macOS native libraries.

## 0.0.1

- Compile main and string-literal print calls to standalone macOS ARM64 executables.
