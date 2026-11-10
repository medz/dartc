## Unreleased

The development checkout uses analyzer 14.7.0 to resolve Dart source, produces verified IR and builds native integer, double and pointer library exports and programs. Executables support synchronous, parameterless main functions. Object construction and reclamation work within synchronous native entries; persistent managed state, asynchronous execution and complete standard library support remain unimplemented. Existing native compiler downloads remain available in [0.5.0](https://github.com/medz/dartc/releases/tag/v0.5.0).

- Allocate objects, execute constructors and reclaim unreachable objects within synchronous native calls and standalone programs. Preserve live references through collection, nested constructors and native reentry; release the entry's heap on return. Allocation failure currently reports an uncaught error and exits; catching it and unwinding Dart exception handlers remain unsupported.

- Build and inspect typed SSA graphs with explicit calls, storage, effects, exception edges and asynchronous suspension. Verification seals referenced type metadata and rejects conflicting declaration identities, invalid field references and incomplete constant storage.
- Lower Dart control flow, patterns, collections, closures, generics, classes, enums, mixins and extension types. Async functions, synchronous and asynchronous generators, and `await for` preserve cleanup and cancellation paths. Assertions can be enabled with `Lowering(enableAssertions: true).lower(input)`.
- Preserve constructor-alias type mappings and function identity, including erased extension-type constructors. Inherited method entries remain distinct from abstract interface signatures, preserving covariant checks and defaults.
- Lower deferred imports with independent prefix identities, asynchronous loading and checks before argument evaluation. Ordinary SDK calls and imported extension types retain external targets when their implementations are outside the supplied library batch.
- Build `@Export<Int64 Function(...)>` functions as Mach-O or ELF objects, static libraries and shared libraries, with matching C/C++ headers. Native bodies support integer constants, addition, subtraction, multiplication, bitwise AND/OR/XOR/NOT, comparisons, boolean expressions, branches, loops and direct calls across Dart libraries. Parameters use registers and the stack; frames preserve values across branches, loop iterations and recursive calls. Linking, archive indexes and Mach-O ad-hoc signing are implemented in Dart, with no external native toolchain dependency.
- Build standalone programs with `--kind exe` or `Output.executable()`. Select main from the first library's exported namespace, including re-exports; normal completion ignores its Dart return value and exits with status zero. `Compilation.write` sets executable permissions. `Linker.linkExecutable` also accepts a global code symbol directly, including archive roots. Linux executables currently require statically resolved inputs and use fixed addresses; macOS executables use system dyld and support explicit shared-library dependencies. Parameter lists, async entries, Linux dynamic executable linking and PIE remain unimplemented.
- Use target-specific `CodeGenerator` and `CallingConvention` implementations, instance-based object formats and a memory-only `Linker`. Modules distinguish local definitions, globally linkable symbols and public exports. Select an explicit target.
- Compile `@Native<T>` top-level and static functions with explicit asset/symbol bindings through `Compiler.compile(nativeSymbols: ..., linkInputs: ...)`. Preserve `DefaultAsset`, library URI defaults, constant aliases, inferred pointer/void signatures and `isLeaf`. Missing referenced bindings fail explicitly. The independent `CodeGenerator.generate(imports: ...)` API accepts `NativeImport` bindings. Outgoing calls convert native integer widths and Float precision, preserve live Dart values and support platform-specific stack arguments. Automatic asset discovery, runtime resolver fallback and managed call transitions remain unimplemented.
- Pass and return `Pointer<NativeFunction<T>>`, nested native pointers and `Pointer<Void>` through library exports, preserving signatures in C headers and addresses across Dart calls, branches and loops. Pointer equality compares addresses even when element types differ. `NativeCall` invokes typed function pointers through the independent IR API; source `asFunction` calls lower to capturing closure IR, whose native execution remains unimplemented. The development API exposes `NativeTypeRef` values in `NativeSignature.result` and `parameters`; use `NativeSignature.types` to construct nested descriptions. The constructor taking FFI type literals remains available.
- Export signed and unsigned 8-, 16-, 32- and 64-bit integers, pointers to those native types, and `Void` results, with matching C declarations. Native boundaries extend and truncate integer values, including platform-specific stack layouts; Dart calls to annotated functions retain full Dart integers. Construct pointers from addresses, recover addresses, compare pointers and read or write native integer storage without changing adjacent bytes. Pointer values survive calls, branches and loops; aliased writes and compound assignments preserve Dart evaluation order. Callers retain responsibility for storage lifetime and alignment.
- Export `Float` and `Double` parameters and results alongside integers and pointers. `Float` boundaries and `Pointer<Float>` storage use 32-bit precision while ordinary Dart calls and variables retain double precision. `Pointer<Double>` provides 64-bit reads and writes. Generate double constants, negation, arithmetic and comparisons on ARM64 and x86-64, including NaN, infinities and signed zero. Floating values survive loops, register pressure and calls; excess mixed arguments use the stack.
- Offset native scalar pointers with `+`, `-` and `elementAt`, and read or write elements with `[]` and `[]=`. Offsets count elements, including negative indices; indexed updates preserve receiver, index and right-hand-side evaluation order and aliasing. Address calculations retain the target pointer width without accessing memory.
- Use mixed `int`/`double` arithmetic, integer `/` and `toDouble` with known numeric representations. Mixed comparisons retain integer precision beyond 2^53 and at the 64-bit boundaries. Constants, defaults, constructor initializers and export annotations use the same comparison rules, including equality of positive and negative zero. Constant evaluation errors are checked before lowering, including unused declarations and unreachable code. Valid const assertions and assignments are no longer rejected solely because upstream evaluation rounded the values. Collection element types, duplicate elements and keys, and pattern exhaustiveness use the corrected constants while preserving static checks in skipped branches.
- Call Dart helpers with optional or named parameters and constant defaults from native functions. Exported FFI signatures continue to require positional parameters.
- Assemble and link cross-module reads and writes to read-only, writable and zero-initialized data. Mach-O/ELF objects and archives preserve section identities, data symbols, calls and address relocations. Shared libraries separate executable, read-only and writable mappings; BSS reserves zero-initialized memory without storing its bytes in the file. Dart global-variable initialization and data export annotations remain unimplemented.
- Read supported Mach-O/ELF object files with `ObjectFormat.decodeObject` and link their modules directly. Readers preserve local and global symbol identities, aliases, exports and unresolved references, validate record bounds and reject unsupported sections or relocation forms. Weak symbols remain unimplemented.
- Call functions and reference data or function addresses in separate shared libraries with `LinkInput.sharedLibrary(name, symbols: ...)`, including through `Compiler.compile(linkInputs: ...)`. Bindings preserve local aliases and native symbol names. Mach-O uses the named dependency; ELF uses global symbol lookup. Required dependencies are retained even without symbol references, and missing libraries or symbols fail at load time. Indirect address relocations also support local and statically linked definitions, with pointers adjusted when the output is loaded.
- Read indexed GNU and little-endian Darwin static libraries with `Archive.decode`. Link ordered objects and archives, selecting members only when needed by unresolved symbols. Linux searches archives at their input positions; macOS includes explicit objects first and revisits archives as new references appear. Unselected object contents are not decoded. Thin archives, 64-bit indexes and archives without an index remain unsupported.
- Manage checked input with `AnalysisSession` from `package:dartc/frontend.dart`. `await Lowering().lower(input)` returns `program`, `entryPoint`, `exports` and `imports`; the entry and binding maps use the program's declaration identities, and `imports` retains unresolved `NativeReference` values. Analysis can include the non-SDK dependency closure, checking unused declarations and preventing source suppressions or editor settings from hiding language errors.
- Bundle the original Dart SDK 3.13.7 standard library sources and license at a fixed official commit. The standalone compiler works without an installed SDK, source cache or network access; declared project dependencies remain separate. `const DartSdk().files` exposes the verified source text. The development-only `SdkResolver`, `DartSdk.at/current`, `--sdk` and SDK selection parameters have been removed.
- Compile non-captured scalar locals initialized after declaration, preserving integer, boolean, double and pointer values across branches, loops and calls. Native generation rejects uninitialized reads, escaping or aliased cells, and unsupported late storage.
- Remove the development-only `runtime/platform/io.dart` source API.
- Compile direct `dart:math.sqrt` calls with known `int` or `double` inputs in native libraries and executables, preserving negative zero, NaN and infinities.
- Lower referenced SDK top-level functions and static methods from their original Dart bodies, including calls through re-exports and function values. `Lowering.lower` is now asynchronous. Native execution still requires implementations for every referenced operation and callable, including error constructors.
- Store symbol addresses in read-only or writable data with `Relocation.address(section, offset, symbol)`. ELF and Mach-O objects, archives and linked outputs preserve these references, including across shared libraries; read-only storage is protected after loading. Instruction references now use `Relocation.instruction(...)` and the `InstructionRelocation` subtype. Address fields require eight-byte alignment and do not support symbol addends.
- Generate immutable object constants and direct field reads through `CodeGenerator`, including inherited fields and nested references. Integer and double constants, and boolean values, can enter reference storage; generic fields and member calls unbox known scalar results. References retain their values across calls, stack arguments and control flow. `package:dartc/layout.dart` provides 64-bit object sizes, field offsets and reference slots. Runtime numeric boxing, virtual member calls and complete Dart class execution remain unimplemented.
- Preserve distinct NaN bit patterns in IR constant identity, including nested constant objects. Numerically equal positive and negative zero also retain distinct constant identities.
- Compile null comparisons, `??`, `??=` and type tests whose results follow from static types and null checks. Nullable scalar values retain their representations across calls and control flow, and short circuits preserve required side effects. General runtime type checks, checked casts, null assertions and boxing computed integers or doubles remain unimplemented.
- Omit unused block-argument transfers and dead register saves in native control flow. Operand evaluation, calls and writes still run, and live values survive branches and loop backedges.
- Generate stack records for references live across calls, with frame linkage and explicit native entry boundaries. References reload from their stack slots after calls; integers and native pointers remain untraced. `StackRoots` in `package:dartc/layout.dart` reads and writes these records.

Language support and known analyzer differences are tracked in [specs](specs/README.md). IR behavior checks do not establish native execution support or full Dart compatibility.

Development-only type and constant helpers have moved to their owning values:

| Previous helper | Replacement |
| --- | --- |
| `substituteType(type, environment)` | `type.substitute(environment)` |
| `typeParametersIn(type)` | `type.freeTypeParameters` |
| `rebindFunctionType(signature, environment)` | `signature.rebind(environment)` |
| `containsCovariantTypeParameter(type, parameters)` | `type.requiresCovariantCheck(parameters)` |
| `constantKey(value)` | `value.structuralKey` |

SDK member selection belongs to lowering. Callers of the removed `coreCollectionOperation` helper should construct typed IR operations such as `ListSublist` and `MapContainsKey` directly.

Import `Export` from `package:dartc/interop.dart`, alongside `NativeSignature`, `NativeExport` and `NativeExports`. The separate development entry `package:dartc/export.dart` has been removed; annotation syntax and native signatures are unchanged.

`LinkInput.sharedLibrary` and `SharedLibraryInput` use `symbols` instead of `functions` for their binding map, covering function calls and address imports.

`NativeSignature` now takes actual `dart:ffi` type values: use `NativeSignature(Int64, [Int64, Int64])` instead of `NativeSignature.int64(2)`. It accepts fixed-width integers, `Float`, `Double`, pointers to these scalars and a `Void` result. `NativeTypeLayout` exposes supported type sizes, pointer types and C spellings. `CallLayout.result` is nullable for void functions. Architecture-specific ABI results use `CpuRegister`, whose `Register` and `FloatRegister` variants keep general and floating locations distinct. `CallLayout.scalars` replaces `CallLayout.words` with separate parameter banks and result registers; `packedStack: true` selects Apple ARM64 scalar stack packing. `StackArgument.size` records each slot's occupied bytes.

`LoadNative` and `StoreNative` replace the integer-specific IR operations. Their pointer's element type determines the Dart value type, storage width and conversion. `FfiTypes.scalarTypes` replaces `integerTypes` and includes the floating declarations. `PointerFromAddress` now requires the pointer type as its second argument; use `FfiTypes.pointerTypes[Pointer<Float>]!`, for example.

`PointerOffset(pointer, index)` retains the pointer's element type and expresses an element offset independently of its machine layout. ARM64 `Assembler.add` accepts a left `shift`; x86-64 `Assembler.lea` computes a base plus a scaled index without accessing memory.

`ObjectModule` takes `Section` values instead of one code buffer. `Symbol` and `Relocation` take a section index before the byte offset; data symbols use `kind: SymbolKind.data`. The x86-64 assembler's `load` and `store` methods accept a base register, replacing `loadStack` and `storeStack`; pass `Register.rsp` for stack access.

Symbols can appear in any order and may overlap or alias. `Symbol.size` is nullable, and `SymbolKind.unknown` preserves a missing kind. Mach-O symbols have neither an extent nor a function/data type; ELF retains those fields when present. Callers must handle absent information instead of inferring it from neighbouring symbols.

`Linker.linkSharedLibrary` now accepts `LinkInput` values: wrap each module with `LinkInput.object(module)` and each decoded archive with `LinkInput.archive(archive)`. On Linux, place an archive after the objects that reference it; repeat an earlier archive when a later one introduces references back to it.

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
