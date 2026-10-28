## Unreleased

- Add lazy `late` locals, captured variables, top-level/static variables and typed instance fields, with final assignment checks and reentrant initialization.
- Add native double literals, arithmetic and `/`, including mixed numeric values, constants, nullable values, generics and collections.
- Add decimal parsing and shortest round-trip formatting, numeric conversions, comparisons and double constants/properties.
- Advance the source runtime ABI to 15 for boxed doubles and numeric metadata. Keep compiler, runtime and layout inputs matched when rebuilding.

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
