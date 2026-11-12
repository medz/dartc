## Unreleased

- Read and write fixed inline FFI arrays, including nested arrays, native pointers and struct/union elements. Array views retain their backing storage through collection; indexed accesses check bounds, and array assignments copy into the destination storage.
- Use scalar typed lists and ByteData with shared buffer views, endian-aware access, overlapping copies and read-only views. Struct/Union constructors accept TypedData with element offsets; scalar Array.elements views share their native storage. SIMD lists still require implementations.

- Compile List, ordered Map and UTF-16 String implementations from Dart source alongside user code. Direct IR clients now supply checked SDK bodies for these operations; `IrClass` describes traced variable payloads and constant List storage, and `NewPayload` allocates that storage.
- Pass FFI structs and unions by value through exports, imports and native function pointers. Support packed and nested fields, owned storage and typed native states on macOS ARM64 and Linux ARM64/x86-64. C headers include referenced aggregate definitions. Add `Bool`, `IntPtr` and `UintPtr` scalar bindings.
- Keep local logical-or pattern variables in their own closure scope. SDK static methods are lowered when referenced.

- Generated IR classes and functions no longer require a library URI. Pass a null library and retain the same definition object for references; `MemberSelector.privateScope` and `FunctionTarget.privateSelectorScope` preserve source-library or generated-class privacy. Missing generated definitions are rejected. `LoweringResult.runtime` carries bound runtime contracts without retaining analyzer state.
- Use the SDK's Dart `HashMap` implementations for ordinary, identity and custom equality maps, including Zone storage.

Build a standalone development compiler with `dart run tool/build.dart`. Standard-library and private runtime sources are stored as an indexed binary resource in the executable; source builds use the same archive from the package. Programmatic callers supply `Compiler(target, resources: ...)` with a `SourceArchive`. `AnalysisSession(paths, sdk: ...)` selects a `DartSdk`; private sources require an explicit `sourceArchive`.

`AnalysisSession(resources: ...)` selects libraries from the private source archive to check alongside file inputs. `Compiler` compiles the Dart runtime automatically, including initialization, allocation, precise mark and sweep collection and cleanup. The collector owns ordinary Dart objects in separate control storage and reuses empty heap pages. Direct `CodeGenerator.generate` callers generating managed code supply `runtime: HeapRuntime(...)` with a checked program, allocation, release, event and overlap-safe byte-copy entries, and explicit memory services. Functions marked `NonAllocating` are checked after representation selection to reject allocation, exceptions and foreign calls throughout their call graphs.

Rebuild native objects when updating: object headers grow from 32 to 40 bytes and storage descriptors add weak-reference and conditional key/value slots. `IrClass` and `ObjectLayout` accept these tracing declarations. Public `WeakReference`, `Expando` and `Finalizer` use these slots; `NativeFinalizer` remains unimplemented.

The development checkout uses analyzer 14.7.0 to resolve Dart source, produces verified IR and builds native integer, double and pointer library exports and programs. Executables support synchronous, parameterless main functions. Object construction and reclamation support synchronous native entries and persistent managed globals; concurrent calls, cross-thread execution, cross-module managed values, async/await and complete standard library support remain unimplemented. Existing native compiler downloads remain available in [0.5.0](https://github.com/medz/dartc/releases/tag/v0.5.0).

- Run `Finalizer<T>` callbacks as events after microtasks, in their creation Zone, with nullable tokens, multiple attachments and cancellation through `detach`. Callbacks can allocate, collect and reenter native code; collection itself never runs user callbacks. Support `scheduleMicrotask`, `Timer`, `Timer.run` and `Timer.periodic`, including cancellation and Zone error handling. Standalone programs drain events after main; synchronous library calls drain events before the outermost call returns, so an active periodic timer keeps that call running. Heap shutdown discards remaining attachments without forcing callbacks. See [Finalizer tests](test/compiler/finalizers_test.dart).
- Compile numeric `abs`, `sign`, classification getters, `compareTo` and `clamp`, including `num` receivers and method values. Preserve integer precision, NaN ordering, negative zero and invalid-bound errors. Boxed `num` values support addition, subtraction, multiplication, division, negation and conversion to double across calls and returns. See [numeric method tests](test/compiler/numeric_methods_test.dart).
- Resolve constant aliases of `Native` and `DefaultAsset` with complete SDK implementation checks. Preserve inherited Object declarations in IR, including `toString` method identity through direct `super` access and virtual lookup; native identity, hash and runtime type operations continue to honor user overrides.
- Compile mutable Map literals and `Map()` with ordered keys, indexed reads and writes, `containsKey`, `remove`, `clear`, key/value/entry iteration and inherited Map operations. Preserve original keys on updates, runtime key/value checks, user overrides and exceptions, including allocating hash/equality callbacks and maps retained across native calls. Const Maps and `HashMap` default, custom equality/hash and identity construction are also supported. See [Map tests](test/compiler/maps_test.dart) and [Zone map tests](test/compiler/finalizers_test.dart); literal Map spreads and the remaining factories still need native implementations.
- Compile SDK factory constructors with Dart bodies, including their redirect targets and instance storage. This enables ordinary SDK iterable factories used by Map entries.
- Compile mutable and const List literals, `List.empty`, `List.filled`, `List.of` and `List.from`, indexed reads and writes, `elementAt`, `sublist`, `add`, `addAll`, literal spreads and length changes. Preserve constant identity, generic element checks, shared fill values, mutation restrictions and references through collection and persistent globals. See [List tests](test/compiler/lists_test.dart) for the native scope.
- Copy List ranges and list-pattern rest elements into independent, growable lists while retaining shared element objects and their actual generic type. Preserve user `sublist` overrides, method values and defaults. `List.of` checks the iterable's type before iteration; `List.from` checks each element. IR clients can use `ListFrom` to copy an iterable with an explicit result type and growability.
- Iterate Lists and user-defined Iterable/Iterator implementations with synchronous `for-in`, including extracted `moveNext` methods, length-change errors, exception cleanup and iterators saved across native calls. `addAll` checks its iterable argument before iteration; literal spreads check elements individually and preserve evaluation order. Other collection APIs still require native implementations.
- Construct strings with `String.fromCharCodes`, including selected ranges, constructor values, user-defined Iterables and supplementary Unicode code points. Read `String.codeUnits` through the SDK's unmodifiable List implementation, retaining the string across collection and later calls. See [string tests](test/compiler/strings_test.dart), including native character input and UTF-16 output buffers.
- Compile inherited SDK mixin bodies and static calls through class type aliases. IR clients can construct `StringFromCharCodes` with typed character codes and optional range operands; its effects include iterator calls.
- Construct strings with `String.fromCharCode`, concatenate with `+` and read individual UTF-16 units with `[]`. Strings retain their contents through collection and persistent globals; equality and hashes use their contents, including through Object views. Invalid character codes and indices throw catchable RangeError. See [string tests](test/compiler/strings_test.dart).
- Read string lengths and UTF-16 code units with `String.length` and `codeUnitAt`, including generic receivers and extracted method values. Out-of-range reads preserve evaluation and cleanup order. IR clients can use `StringLength`, `StringCodeUnitAt` and `StringFromCharCode`.
- Reinterpret pointer element types with `Pointer.cast<T>()`, including generic functions, nullable receivers and extracted method values. Preserve the address without accessing native memory. Function comparisons with null remain valid when bound method values are present.
- Preserve FFI pointer objects through generic calls, nullable storage, captures and collection. Native boundaries continue passing raw addresses, including calls through `asFunction` closures. Compile `identical` calls and function values with integer value identity and double bit identity. See [pointer and identity tests](test/compiler/pointer_values_test.dart).
- Produce identical shared-library output when linking modules directly or after an object-file round trip. `ObjectModule.relocations` is ordered by section and patch offset.
- Change the development IR memory API to `LoadNative(address, nativeType)` and `StoreNative(address, nativeType, value)`, using an integer address and `NativeScalarType`. Reads and writes preserve the declared native width and precision; callers using a Dart pointer extract its address with `PointerAddress`. Source-level FFI APIs are unchanged.
- Compile local and captured `late` and `late final` bindings with lazy initialization, retries, recursive reads and checked writes. Preserve null values, lexical generic types and initializer side effects through exceptions, collection and later native calls. Release the initializer closure after binding. See [native late-local tests](test/compiler/late_locals_test.dart).
- Resolve generated function dependencies before producing native code, including checks used by allocation and exception helpers. `CodeGenerator.generate` consistently rejects incomplete source definition sets, including programs that need numeric helpers.
- Preserve actual `void` results through Dart calls, function values, `finally` and collection, including legal wider return views. Native `Void` calls return null to Dart. Check `Never` parameters before entering method bodies, preserving argument evaluation and exception cleanup through direct and extracted method calls.

- Keep scalar, reference, nullable and `num` top-level variables and class statics across native calls. Lazy initialization runs on the first read, retries after failure and preserves writes performed before an exception. Generic classes share their static declaration storage. Support final, late and late final globals, with catchable SDK LateError failures and RHS/type checks before repeated-binding checks.
- Compile instance `late` and `late final` fields for represented scalar, reference, nullable and generic types. Independent bound flags distinguish null from uninitialized values and preserve per-instance and inherited declaration identity. Constructor writes bind fields; lazy initializers receive the actual receiver and type arguments. Preserve retries, committed writes on failure, recursive initialization and GC roots. Assignment RHS and actual generic type checks precede final-binding checks; invalid generic late-final writes are rejected even where the fixed SDK accepts them.
- Compile synchronous local and anonymous functions that capture values or shared non-late mutable cells. Closures can outlive their creator and persist through globals; typed calls use the actual target's positional/named defaults, preserve recursion and loop iteration identity, and retain their own generic arguments and enclosing function/class type environments. Runtime types use the actual function signature, and captured references participate in normal collection and exception cleanup. See [closure tests](test/compiler/closures_test.dart).
- Use top-level functions, static methods and constructors as native function values, including generic functions and constant specializations. Preserve default arguments, canonical identity, constructor aliases and factory redirects through ordinary calls, collection and exception cleanup. Dynamic/noSuchMethod calls and FFI callbacks remain unsupported. See [function-value tests](test/compiler/function_values_test.dart).
- Extract instance and `super` methods as typed function values, retaining the selected implementation, receiver, generic environment and default arguments. Invalid extraction signatures throw before later arguments run; covariant arguments are checked at invocation. Bound method equality uses receiver identity and the selected method, including after collection. Equality and hashing also work through Object and Function views; equal functions retain equal hashes through collection without calling receiver overrides. Dynamic member dispatch remains unsupported. See [bound-method tests](test/compiler/bound_methods_test.dart).
- Instantiate generic function values explicitly or by inference at runtime, including closures, methods and constructors. Retain lexical type arguments, shared captures, receivers and default arguments through collection and exceptions. Compare instantiations by their source function and all type arguments, including arguments absent from the signature and equivalent constant instantiations. See [function-instantiation tests](test/compiler/function_instantiation_test.dart).
- Tear off constructors using lexical type arguments, including `C<T>.new`, named constructors, aliases, redirecting factories and extension types. Preserve enclosing class/function types and defaults through collection and across native entries. Reading callbacks through a wider generic receiver now checks the result before subsequent caller effects, including ordinary and late fields. See [constructor callback tests](test/compiler/function_instantiation_test.dart).
- Allocate objects, execute constructors and reclaim unreachable objects within synchronous native calls and standalone programs. Modules with reference globals retain their heap across calls and share roots during same-module, single-threaded synchronous reentry, including suspended outer frames. Modules without reference globals release activation-local heaps on return; standalone programs explicitly release their heap before exit. Allocation failure currently reports an uncaught error and exits; catching allocation failures remains unsupported.
- Release persistent module heaps when a shared library linked by dartc unloads. `Section.finalizers` holds address relocations to local code using the native void/no-argument cleanup ABI. ELF uses `.fini_array`; the Mach-O linker registers cleanup with `__cxa_atexit`, since legacy terminator metadata alone does not ensure unload callbacks on the host. Linking raw Mach-O objects with an external system linker does not provide this unload guarantee. Executable linking rejects inputs containing finalizer sections; compiler-generated standalone entries release explicitly and emit none.
- Compile synchronous `throw`, `catch`, `rethrow` and `finally`, including cross-function and constructor failures. Preserve exception identity and captured call frames through collection; a new throw captures a new trace, while rethrow keeps the original. Exceptions escaping a native entry terminate with status 255. Stack trace formatting and `Error.stackTrace` access remain unimplemented.
- Compile integer `~/`, `%` and `remainder`, including negative operands and signed 64-bit overflow. Division by zero throws `IntegerDivisionByZeroException` through normal catch/finally paths, even when the result is unused. Modulo remains nonnegative; remainder follows the dividend's sign.
- Compile floating and mixed `~/`, including boxed `num`. Divide as double before truncating, saturate finite overflow and throw catchable `UnsupportedError` for non-finite quotients; retain exact integer division when both operands are integers. Division-by-zero error properties use the SDK class bodies.
- Compile integer `<<`, `>>` and `>>>`, including compound assignments, 64-bit overflow and counts of 64 or more. Negative counts throw `ArgumentError` with the original count as its message, preserving operand evaluation and cleanup. ArgumentError constructors and properties use the bundled SDK Dart bodies.
- Compile `toInt`, `truncate`, `floor`, `ceil` and `round` for `int`, `double` and boxed `num`. Preserve halfway rounding, integer precision, finite overflow saturation and catchable `UnsupportedError` for non-finite values. Error messages use real string constants and ordinary SDK constructors.
- Compile `truncateToDouble`, `floorToDouble`, `ceilToDouble` and `roundToDouble` for `int`, `double` and boxed `num`. Preserve negative zero, non-finite values and large integral doubles without integer-range saturation.
- Preserve UTF-16 string constants and their canonical identity in native modules, including empty strings and unpaired surrogates. SDK `RangeError.checkNotNegative` now runs both success and failure paths with its original error fields. General string operations and formatting remain unimplemented.
- Use `is`, `is!` and ordered `on T` catches with native scalar and class values, including inherited interfaces and generic arguments. Function type parameters support `is T`, `is! T`, `is T?` and `as T`. Checks use actual value types and preserve function variance, lexical bounds and inherited type arguments. Checked casts and postfix null assertions preserve values on success and throw catchable TypeError on failure, retaining evaluation and cleanup order. Direct class members use actual receiver type arguments, including inherited substitutions.
- Call generic Dart functions with concrete or forwarded type arguments, including recursive calls and arguments passed on the stack. Preserve scalar values across generic calls and collection; read a function's type argument through `T`, form nullable, nominal, FutureOr, function and record types at runtime, and compare their normalized structures. Generic function bounds can depend on enclosing function arguments, including nested and chained binders. Type equality also works through variables, parameters and returned values, preserving custom Type operators, inherited identity comparison and the null rule. Built-in Type hashing uses the same normalized structure as equality and remains stable through collection. Type formatting remains unimplemented.
- Read `runtimeType` for native scalar, null, pointer, class and Type values, including boxed values and constants. Preserve actual generic arguments across calls and collection. User getter overrides retain their results, side effects and exceptions through inheritance, interface views, generic receivers and object patterns; super calls use the selected ancestor. Pointer runtime types use `Pointer<Never>`; static element types still determine native signatures and storage access.
- Pass scalar arguments to generic constructors using the initializer's declared representations, preserving them through allocation and nested collection. FFI addresses and indices accept type parameters bounded by `int`; stored values accept the corresponding `int` or `double` bound. Construct `C<T>` with runtime arguments and call generic factories with the requested class type. Generic field writes check the actual receiver before modifying storage; rejected writes throw TypeError and preserve the old value.
- Call native class methods, getters, setters and operators through concrete or abstract interfaces, including inherited and mixin implementations. Use the selected implementation's defaults, preserve argument evaluation order and check covariant parameters and generic bounds before entering the body. Return values retain their representations through collection and exception cleanup. Other Object members, Never parameters and value-returning views of void implementations remain unimplemented.

- Build and inspect typed SSA graphs with explicit calls, storage, effects, exception edges and asynchronous suspension. Verification seals referenced type metadata and rejects conflicting declaration identities, invalid field references and incomplete constant storage.
- Inspect direct callable dependencies with `IrCallable.callees` and virtual declarations with `virtualMembers`. `IrProgram.reachableFrom(roots)` selects direct and nominal member dependencies for closed programs; dynamic invocation and managed inputs from other modules are not included.
- Normalize IR Type values, nested constant identities and instantiated function equality and hashing, including generic function parameters bounded by Never. `ValueType.normalize()` provides runtime type identity without changing static binder equality or discarding callable metadata.
- Lower Dart control flow, patterns, collections, closures, generics, classes, enums, mixins and extension types. Async functions, synchronous and asynchronous generators, and `await for` preserve cleanup and cancellation paths. Assertions can be enabled with `Lowering(enableAssertions: true).lower(input)`.
- Preserve constructor-alias type mappings and function identity, including erased extension-type constructors. Inherited method entries remain distinct from abstract interface signatures, preserving covariant checks and defaults.
- Lower deferred imports with independent prefix identities, asynchronous loading and checks before argument evaluation. Ordinary SDK calls and imported extension types retain external targets when their implementations are outside the supplied library batch.
- Build `@Export<Int64 Function(...)>` functions as Mach-O or ELF objects, static libraries and shared libraries, with matching C/C++ headers. Native bodies support integer constants, addition, subtraction, multiplication, bitwise AND/OR/XOR/NOT, comparisons, boolean expressions, branches, loops and direct calls across Dart libraries. Parameters use registers and the stack; frames preserve values across branches, loop iterations and recursive calls. Linking, archive indexes and Mach-O ad-hoc signing are implemented in Dart, with no external native toolchain dependency.
- Build standalone programs with `--kind exe` or `Output.executable()`. Select main from the first library's exported namespace, including re-exports; normal completion ignores its Dart return value and exits with status zero. `Compilation.write` sets executable permissions. `Linker.linkExecutable` also accepts a global code symbol directly, including archive roots. Linux executables currently require statically resolved inputs and use fixed addresses; macOS executables use system dyld and support explicit shared-library dependencies. Parameter lists, async entries, Linux dynamic executable linking and PIE remain unimplemented.
- Use target-specific `CodeGenerator` and `CallingConvention` implementations, instance-based object formats and a memory-only `Linker`. Modules distinguish local definitions, globally linkable symbols and public exports. Select an explicit target.
- Compile `@Native<T>` top-level and static functions with explicit asset/symbol bindings through `Compiler.compile(nativeSymbols: ..., linkInputs: ...)`. Preserve `DefaultAsset`, library URI defaults, constant aliases, inferred pointer/void signatures and `isLeaf`. Missing referenced bindings fail explicitly. The independent `CodeGenerator.generate(imports: ...)` API accepts `NativeImport` bindings. Outgoing calls convert native integer widths and Float precision, preserve live Dart values and support platform-specific stack arguments. Automatic asset discovery, runtime resolver fallback and managed call transitions remain unimplemented.
- Pass and return `Pointer<NativeFunction<T>>`, nested native pointers and `Pointer<Void>` through library exports, preserving signatures in C headers and addresses across Dart calls, branches and loops. Pointer equality compares addresses even when element types differ. `NativeCall` invokes typed function pointers through the independent IR API; source `asFunction` calls create ordinary capturing closures that remain callable after their creator returns and after collection. The development API exposes `NativeTypeRef` values in `NativeSignature.result` and `parameters`; use `NativeSignature.types` to construct nested descriptions. The constructor taking FFI type literals remains available.
- Export signed and unsigned 8-, 16-, 32- and 64-bit integers, pointers to those native types, and `Void` results, with matching C declarations. Native boundaries extend and truncate integer values, including platform-specific stack layouts; Dart calls to annotated functions retain full Dart integers. Construct pointers from addresses, recover addresses, compare pointers and read or write native integer storage without changing adjacent bytes. Pointer values survive calls, branches and loops; aliased writes and compound assignments preserve Dart evaluation order. Callers retain responsibility for storage lifetime and alignment.
- Export `Float` and `Double` parameters and results alongside integers and pointers. `Float` boundaries and `Pointer<Float>` storage use 32-bit precision while ordinary Dart calls and variables retain double precision. `Pointer<Double>` provides 64-bit reads and writes. Generate double constants, negation, arithmetic and comparisons on ARM64 and x86-64, including NaN, infinities and signed zero. Floating values survive loops, register pressure and calls; excess mixed arguments use the stack.
- Offset native scalar pointers with `+`, `-` and `elementAt`, and read or write elements with `[]` and `[]=`. Offsets count elements, including negative indices; indexed updates preserve receiver, index and right-hand-side evaluation order and aliasing. Address calculations retain the target pointer width without accessing memory.
- Use mixed `int`/`double` arithmetic, integer `/` and `toDouble` with known numeric representations. Mixed comparisons retain integer precision beyond 2^53 and at the 64-bit boundaries. Constants, defaults, constructor initializers and export annotations use the same comparison rules, including equality of positive and negative zero. Constant evaluation errors are checked before lowering, including unused declarations and unreachable code. Valid const assertions and assignments are no longer rejected solely because upstream evaluation rounded the values. Collection element types, duplicate elements and keys, and pattern exhaustiveness use the corrected constants while preserving static checks in skipped branches.
- Call Dart helpers with optional or named parameters and constant defaults from native functions. Exported FFI signatures continue to require positional parameters.
- Assemble and link cross-module reads and writes to read-only, writable and zero-initialized data. Mach-O/ELF objects and archives preserve section identities, data symbols, calls and address relocations. Shared libraries separate executable, read-only and writable mappings; BSS reserves zero-initialized memory without storing its bytes in the file. Dart global-variable initialization uses module storage; data export annotations remain unimplemented.
- Read supported Mach-O/ELF object files with `ObjectFormat.decodeObject` and link their modules directly. Readers preserve local and global symbol identities, aliases, exports and unresolved references, validate record bounds and reject unsupported sections or relocation forms. Weak symbols remain unimplemented.
- Call functions and reference data or function addresses in separate shared libraries with `LinkInput.sharedLibrary(name, symbols: ...)`, including through `Compiler.compile(linkInputs: ...)`. Bindings preserve local aliases and native symbol names. Mach-O uses the named dependency; ELF uses global symbol lookup. Required dependencies are retained even without symbol references, and missing libraries or symbols fail at load time. Indirect address relocations also support local and statically linked definitions, with pointers adjusted when the output is loaded.
- Read indexed GNU and little-endian Darwin static libraries with `Archive.decode`. Link ordered objects and archives, selecting members only when needed by unresolved symbols. Linux searches archives at their input positions; macOS includes explicit objects first and revisits archives as new references appear. Unselected object contents are not decoded. Thin archives, 64-bit indexes and archives without an index remain unsupported.
- Manage checked input with `AnalysisSession` from `package:dartc/frontend.dart`. `await Lowering().lower(input)` returns `program`, `entryPoint`, `exports` and `imports`; the entry and binding maps use the program's declaration identities, and `imports` retains unresolved `NativeReference` values. Analysis can include the non-SDK dependency closure, checking unused declarations and preventing source suppressions or editor settings from hiding language errors.
- Bundle the original Dart SDK 3.13.7 standard library sources and license at a fixed official commit. The standalone compiler works without an installed SDK, source cache or network access; declared project dependencies remain separate. `DartSdk.load()` loads the fixed sources; `SourceArchive` reads and verifies individual files without expanding the entire library. The development-only `SdkResolver`, `DartSdk.at/current`, `--sdk` and SDK selection parameters have been removed.
- Compile non-late locals initialized after declaration, preserving represented values across branches, loops and calls. Locals that need no shared storage identity retain stack slots; captured or aliased cells use managed storage. Initialization checks remain separate from zeroing reference storage for GC safety.
- Remove the development-only `runtime/platform/io.dart` source API.
- Compile direct `dart:math.sqrt` calls with known `int` or `double` inputs in native libraries and executables, preserving negative zero, NaN and infinities.
- Lower referenced SDK top-level functions, static methods and generative classes from their original Dart bodies, including inherited members. `Lowering.lower` is asynchronous. SDK factory bodies remain imports; native execution requires implementations for every referenced operation and callable.
- Store symbol addresses in read-only or writable data with `Relocation.address(section, offset, symbol)`. ELF and Mach-O objects, archives and linked outputs preserve these references, including across shared libraries; read-only storage is protected after loading. Instruction references now use `Relocation.instruction(...)` and the `InstructionRelocation` subtype. Address fields require eight-byte alignment and do not support symbol addends.
- Generate immutable object constants and direct field reads through `CodeGenerator`, including inherited fields and nested references. Integers, doubles and booleans can enter reference storage; generic fields and member calls unbox known scalar results. Computed numeric boxes survive collection during argument preparation, calls and control flow. `package:dartc/layout.dart` provides 64-bit object sizes, field offsets and reference slots. Complete Dart class execution remains unimplemented.
- Preserve distinct NaN bit patterns in IR constant identity, including nested constant objects. Numerically equal positive and negative zero also retain distinct constant identities.
- Extend `Value` for downstream compiler representations. Exhaustive switches over `Value` now require a fallback; `Instruction` and `Constant` remain sealed. `IrFunction` rejects foreign SSA definitions even if they override equality.
- Read Object's identity hash through `super.hashCode` in native code. The value survives collection and retained module state, and bypasses the receiver's override. Read virtual hashCode and compare values through Object views, preserving user overrides, exceptions and the null rule. Numeric hashes agree for equal int/double values, including positive and negative zero.
- Require closed types in `FunctionConstant`, including unused type arguments and alias bounds. Use `InstantiateFunction` for lexical type arguments; invalid constant construction now throws `ArgumentError` before graph construction.
- Compile null comparisons, `??` and `??=`. Nullable scalar values retain their representations across calls and control flow, and short circuits preserve required side effects.
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

`LoadNative(address, nativeType)` and `StoreNative(address, nativeType, value)` replace the integer-specific IR operations. They take an integer address and a `NativeScalarType`, which determines the Dart value type, storage width and conversion. `FfiTypes.scalarTypes` replaces `integerTypes` and includes the floating declarations. `PointerFromAddress` requires the pointer type as its second argument; use `FfiTypes.pointerTypes[Pointer<Float>]!`, for example.

`PointerOffset(pointer, index)` retains the pointer's element type and expresses an element offset independently of its machine layout. ARM64 `Assembler.add` accepts a left `shift`; x86-64 `Assembler.lea` computes a base plus a scaled index without accessing memory.

`ObjectLayout` names the descriptor at byte 0, traced runtime type at byte 8, stable identity hash at byte 16 and allocated size at byte 24. Fields start at byte 32; inline payloads follow the fixed fields. `tracesPayload: true` marks the aligned tail as managed reference slots. `LoadObjectReference` and `StoreObjectReference` retain the managed base while accessing those slots; their caller must prove bounds, alignment and matching collector metadata. Rebuild native modules together after these layout and descriptor changes.

`IrCallable.implicitMembers` replaces `objectMembers`, and `Instruction.implicitMember` replaces `objectMember`, covering collection protocols as well as Object operations. `ListFilled` represents filled construction; `NewCollection(growable: value)` also represents fixed-length or growable empty Lists.

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
