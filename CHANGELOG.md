## Unreleased

List and Map patterns support ordered extraction, list rest slices, missing-key checks, nested destructuring and shared lazy reads across alternatives. Irrefutable shape failures throw StateError; contextual casts and assignment writes preserve Dart's failure ordering and atomicity.

IR distinguishes dynamic from Object? and preserves implicit checks for typed storage, arguments, returns, record and collection elements, and boolean contexts. Dynamic receiver/member/operator dispatch remains unsupported. Statements and collection elements now share declaration and loop lowering; ordinary and dot-shorthand calls share their evaluation paths.

Generic top-level functions, static and instance methods, local functions and closures retain scoped type parameters, bounds and runtime type environments. Direct calls, function values and explicit or contextual instantiation preserve inferred type arguments, polymorphic recursion and virtual entry checks. Generic function types compare structurally up to binder renaming.

Generic constructor tear-offs support aliases with reordered, fixed or repeated type arguments and preserve distinct alias identity. Constant and default function values retain type arguments even when those arguments do not appear in their signature. Constant-pattern caches distinguish function and constructor instantiations.

Generic classes retain declaration type parameters and instantiated type arguments throughout IR. Constructors, factories and factory redirects substitute member signatures, superclass and interface types without copying function bodies. Runtime checks and constructor or method tear-offs preserve actual type arguments, bounds, covariance and type environments captured by closures. Const instances remain unsupported.

Mutable typed List, Set and Map literals support conditional and loop elements, patterns, spreads and null-aware elements. Synchronous `for-in` uses the iterator protocol and preserves per-iteration captures, control flow and exceptions. Collection IR includes indexing, writes, length, add and addAll; const collections and the full SDK collection API remain unsupported.

Numeric expressions support `double`, `num` and mixed operands without losing integer precision or floating negative zero. Runtime string interpolation preserves expression and conversion order, including virtual `toString` calls and adjacent or nested literals.

Ordinary and null-aware cascades evaluate their receiver once. Dot shorthand supports constructors, factories, static methods and explicit static getters for supported types. Explicit top-level and static getters/setters support reads, calls and updates.

Non-late locals and `final` variables can be assigned after declaration. Their storage is preserved across branches, exceptions and closures, including uninitialized captured loop bindings. Wildcard declarations retain initializer effects.

Object patterns read instance getters and method tear-offs. Pattern alternatives and switch cases share extracted fields and repeated comparisons without repeating user side effects.

Assertion statements and constructor assertions can be enabled with `Lowering.lower(input, enableAssertions: true)`. Assertions are disabled by default, including closures inside their conditions and messages.

Assignments can target local variables, parameters, instance properties and user-defined index operators. Compound assignments preserve getter and setter order, including the conditional write in `??=`. Integer expressions support division, modulo, bitwise operators and shifts.

Lowering supports ordinary `for` and `do-while` loops, including `break` and `continue` across nested loops and `break` from labeled statements.

Conditional expressions now select one branch and preserve its result, including values passed through `void` parameters and locals.

Direct calls accept optional positional and named parameters with scalar defaults. Lowering also supports string, double and null literals and scalar constants declared locally or at library scope.

Pass top-level functions, bound methods and constructors as values. Indirect calls preserve optional defaults and covariant entry checks. Local functions and anonymous closures can retain and update captured variables after the enclosing call returns. Closures created in a `for` loop retain their iteration's bindings.

Records can be constructed, returned, compared and used as constants or parameter defaults. Named and positional fields support ordinary and null-aware reads. Nested record patterns can declare locals, swap existing variables and initialize `for` loops.

Nullable core types can pass through calls and branches. Lowering supports `??`, local `??=`, postfix `!`, and type tests and casts on core types. Synchronous `throw` and calls returning `Never` end evaluation of the current path.

Synchronous functions can catch explicit throws, failed type checks and exceptions from calls. Typed catch clauses can bind the exception and stack trace, and `rethrow` preserves both. A `finally` block runs on normal completion, return, unwinding and jumps out of the protected code.

Use scalar and record patterns with `when` guards in `if-case`, `switch` statements and `switch` expressions. Switch statements support shared case bodies, implicit breaks and labeled `continue`.

`Lowering.lower` returns an `IrProgram` with `classes` and `functions`. Classes support generative and factory constructors, including redirects to named constructors with optional arguments. Instance methods and getters dispatch on the receiver, including overrides with different defaults and covariant parameters. Runtime type tests and catch clauses follow superclass and interface declarations.

The development checkout pins analyzer 14.7.0 for resolved-metadata compatibility and can print compiler IR. Native executables, libraries and the `Export` API remain available in [release 0.5.0](https://github.com/medz/dartc/releases/tag/v0.5.0).

## [0.5.0](https://github.com/medz/dartc/compare/v0.4.0...v0.5.0) — 2026-10-31

This release adds generic classes, automatic memory reclamation, native-library export declarations and Intel Mac support. Native compiler downloads now work as a single executable. Dart language and standard-library support remains incomplete; see the [versioned specification tracker](https://github.com/medz/dartc/tree/v0.5.0/specs) for supported behavior and gaps.

### Features

- Support generic class instances and const objects, constructor type inference, runtime type-argument checks and generic object patterns.
- Add class modifiers and sealed-class exhaustiveness checking, covariant instance parameters and fields, abstract instance fields, and field-type inference from initializers and interfaces.
- Improve generic call inference using declared bounds and callback context. Support user-defined relational operators in patterns and indexed assignments through `super`.
- Add core error and exception classes. Invalid integer/double parsing, integer division and modulo by zero, supported type checks, invalid character codes and unsupported list mutations now throw catchable Dart errors or exceptions. Preserve the first stack trace attached to an `Error`.
- Add Intel Mac (`macos-x64`) compiler and executable support alongside macOS ARM64 and Linux ARM64/x86-64.
- Export functions and scalar read-only data with `@Export<T>` for macOS and Linux object files, static libraries and shared libraries on ARM64/x86-64. Generate matching C/C++ headers, including mixed integer, double, boolean and pointer signatures.
- Embed required library sources in native compiler binaries, so the compiler can be moved without an accompanying `lib/` directory. Include `package:dartc/export.dart` for native-library projects.
- Report source diagnostics on stderr with file, line, column and source text, including errors in imports and parts. Help and successful build output use stdout.

### Fixes

- Reject output paths that would overwrite source files or package configuration, including symbolic links, hard links and case aliases. Create missing output directories in native builds.
- Preserve source BOMs and handle malformed UTF-8 consistently; reject invalid UTF-8 in package configuration and process arguments.
- Preserve double NaN identity, signs and payloads, including target-specific constants during cross-compilation.
- Fix macOS library export-name encoding and static-archive alignment for Darwin linkers.
- Distinguish bound-method runtime signatures during function type checks.

### Performance

- Reclaim unreachable managed objects, reuse freed storage and release empty allocation regions instead of retaining all allocations until process exit.
- Improve polymorphic calls, ARM64 double register use, common string operations and small pure calls.
- Reduce repeated package lookups, liveness analysis and compiler-buffer allocation during compilation.

### Upgrading from 0.4

- Replace the previous native installation with the 0.5.0 archive. Its `bin/dartc` can be copied anywhere on `PATH`; no adjacent `lib/` directory is required.
- Replace `--export` and `Pointer.fromFunction` export bindings with `@Export<T>` declarations from `package:dartc/export.dart`. Use `--header` to choose the generated header path.
- The SDK-hosted package and source development now require Dart SDK `^3.13.7`.
- The old bootstrap-validation, benchmark and fuzz commands are no longer distributed. Source development uses the standard Dart package tools.

## [0.4.0](https://github.com/medz/dartc/compare/v0.3.0...v0.4.0) — 2026-10-29

This release adds Linux x86-64 binaries and expands native Dart programs with class hierarchies, enums, custom operators, doubles and synchronous exceptions. It remains an early preview, with Dart SDK 3.13.7 as the behavior reference.

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

Replace the complete native archive, keeping its `bin/` and `lib/` directories together. The runtime ABI changes from 14 to 17; compiler, runtime, layout and standard-library files must come from the same release.

For a source build, use the 0.4.0 native compiler for your host as the bootstrap seed. A 0.3 compiler does not understand all the syntax now used by dartc itself:

```sh
dart tool/bootstrap.dart --seed /path/to/dartc-0.4.0-macos-arm64/bin/dartc
```

The SDK-hosted package can be updated with `dart pub global activate dartc 0.4.0`. Language implementation remains incomplete; detailed behavior and gaps are in [specs](https://github.com/medz/dartc/tree/v0.4.0/specs).

## 0.3.0

Early preview release for macOS and Linux ARM64, with Dart SDK 3.13.7 as the behavior reference.

- Add lexical captures to local and anonymous functions, including shared writes, `this`, recursion and per-iteration loop bindings.
- Support bound instance-method values, callable objects and implicit `call` extraction in supported function contexts.
- Support generic top-level and method calls with bounds, partial contextual inference and runtime type arguments, including type-changing recursion; add generic aliases and traditional function typedefs.
- Support switch expressions, if-case, object/List patterns, destructuring declarations and assignments, pattern loops and pattern switch statements with guards and shared case bodies.
- Support cascades, null-aware member/index chains and List conditional, loop, spread and null-aware elements.
- Add static members, named and const constructors, field initializer lists, generative redirection, explicit `new` and constructor aliases.
- Implement `List.insert`, `List.removeAt`, `List.sublist`, `StringBuffer.writeCharCode` and `StringBuffer.isNotEmpty`.
- Update the native runtime ABI from 11 to 14 for captured values, bound methods and heap type metadata. Use the compiler and runtime sources from the same release.
- Reject stale artifacts and incomplete validation evidence; bootstrap keeps the existing verified seed when rebuilding or validation fails.

Language implementation remains incomplete. Current behavior and remaining gaps are tracked in [specs/](specs/README.md).

## 0.2.0

Early preview release for macOS and Linux ARM64.

- Provide standalone native compiler archives with compatible runtime sources.
- Support simple classes, accessors, nullable/reified value checks, canonical const instances and lazy top-level initialization.
- Add noncapturing local and anonymous functions, structural function types and nongeneric type aliases.
- Resolve package configuration v2, language versions, file/package URIs, conditional imports and library parts.
- Include only the runtime components required by the program.

Captures, inheritance, general generics, exceptions, async code and most SDK libraries remain unsupported. Runtime sources and native compiler binaries from older releases must not be mixed with this version.

## 0.1.0

- Compile functions, control flow, strings, lists, and relative imports.
- Build a standalone native compiler that can compile its own Dart sources.
- Generate macOS and Linux ARM64 executables, including local Mach-O signatures in Dart.
- Export explicitly typed FFI callbacks as experimental macOS native libraries.

## 0.0.1

- Compile main and string-literal print calls to standalone macOS ARM64 executables.
