## Unreleased

Mixin applications reuse ordinary class layers, field storage and resolved AST lowering. Each application owns its verified bodies and lexical super bindings, preserving repeated state, initializer order, late closures, private selectors and named application constructors without new IR or runtime body aliases. Generic applications and additional forwarding/covariance cases remain explicit boundaries; see specs/mixins.md.

FutureOr has a dedicated union type rather than a nominal class. Canonical Future identities, normalization, union subtyping, nullable projections, recursive bounds, generic substitution and alpha-equivalent function hashing preserve Dart type semantics. Synchronous type tests, casts, null assertions and reified Type values are checked against the SDK. Native Future execution and async/await remain unsupported.

Synchronous generators lower to explicitly resumable SSA graphs. Each `Yield` publishes a checked element and retains a normal resume edge; a generator `Return` completes iteration rather than returning its public Iterable result. The reference executor gives each iterator a lazy, independent activation while sharing outer capture cells. Synchronous `yield*` checks the entire Iterable<T> and preserves delegated iterator errors, catches and finalizers. SDK differential tests cover laziness, repeated/interleaved iteration, closures, generic methods, cleanup and delegation; same-activation iterator reentry remains an explicit reference-executor boundary. Native coroutine frame/state-machine code generation and asynchronous bodies remain unimplemented.

Ordinary and generic extension types erase through analyzer metadata and ordinary static functions. Primary and secondary generative constructors, this redirects and factory bodies preserve initializer/assertion order, defaults and receiver captures. Representation access, own members/operators, static storage, closures, method and constructor tear-offs, const values and runtime type checks reuse existing IR without nominal allocation. Nullable, dynamic, record, function and collection representations retain their values and evaluation order. Source type arguments retain phantom binders and captured type environments; generic constructors and joint method tear-off defaults reuse ordinary callable machinery. Extension-type interfaces retain source owner substitutions and static bodies, while ordinary interfaces dispatch on the representation with existing covariance checks. Redirecting factories, external constructors and generic constructor-alias extraction remain explicit boundaries; see specs/extension-types.md.

Ordinary extension declarations and direct method calls lower to existing static function targets with an explicit receiver and flattened extension/member type arguments. Implicit, explicit-override and lexical calls preserve analyzer selection, static receiver types, named/default arguments, null shortening and captured receiver/type environments. True static members and globals have qualified identities. Instance accessors, index and unary/binary operators, updates and object/relational patterns reuse the same call adapter. Implicit extension-call invocation reuses the same static targets. Method tear-offs, explicit call extraction and object-pattern method fields use ordinary receiver-capturing closures, preserving generic defaults, fresh binders and per-extraction identity. Two assignment-value evaluation-order differences from SDK 3.13.7 have separate source-order tests and are documented in specs/extension-access.md.

Static runtimeType reads and object-pattern fields reuse existing runtime dispatch, preserving user overrides, actual generic types and getter caching. Direct super.runtimeType uses the selected ancestor implementation. Unmodeled SDK concrete types remain explicit boundaries.

Object.toString through Object and type-parameter views reuses existing dynamic dispatch; super keeps the selected ancestor implementation. Method extraction preserves identity across static, dynamic and pattern access. The fixture interpreter explicitly rejects unmodeled formatting rather than exposing host wrapper types.

Function-valued iterator getters continue into the ordinary function-call path, preserving arguments-before-getter order and avoiding a cast of the getter value in place of the call result.

Indexed updates check read and write key types at their respective calls. A non-null `??=` skips the setter key check, and a failing write key no longer suppresses earlier getter or right-hand-side effects. Ordinary and extension indexes share this fix.

Dynamic throw operands use the ordinary checked conversion to non-null Object before raising, preserving operand identity and evaluation order, catch/finally behavior, and rethrow stack identity. Null produces TypeError.

Own abstract ordinary methods can now emit direct-super covariance wrappers when their complete instantiated signature equals the inherited implementation. Wrappers preserve their own defaults, named argument identity, owner/method generics, lexical super behavior and nSM replacement eligibility, while flattening direct wrapper chains. Interface-only covariance changes and unequal-signature semi-stubs remain guarded.

Foreign-private noSuchMethod obligations retain separate selector and body ownership. Required replacements use the combined interface signature and defaults, including covariant inputs; compatible real and synthetic ancestors remain shared. Bodies construct genuine NoSuchMethodError.withInvocation values and throw through ordinary IR. Public forwarders use statically resolved virtual calls. Error construction is fresh and defers user Invocation getter reads. Nongeneric function instantiation reuses its immutable signature after validating type arguments. Original generic-interface covariance survives specialization and transitive real overrides, including method-bound provenance. Still-unsupported inherited covariance wrappers are rejected before silently selecting wrong defaults or tear-off types.

Function targets convert lazy parameter types once and avoid empty-owner covariance scans. IR verification caches successful type-scope checks by object identity and skips dominator construction for edge-free single-block graphs, retaining the same scope, SSA, operand and control-flow checks.

Dynamic members, function values, operators and updates share one dispatch instruction and existing selector/lvalue lowering. Runtime shape checks precede generic defaults, bounds and parameter checks; getter-call syntax, private names, named evaluation order, assignment values and null shortening are preserved. Ordinary missing members build Invocation for user noSuchMethod or throw NoSuchMethodError. Unmodeled imported/SDK members remain explicit unsupported boundaries. Unary and binary minus have distinct dispatch identities.

Typed noSuchMethod forwarders use ordinary function bodies and one Invocation builder. Entry defaults, bounds, covariance and result checks share existing call machinery; inherited bodies preserve actual defaults and lexical super calls select actual implementations. Typed mirrors retain canonical symbols, declaration-order named arguments and immutable collections. Missing merged generic defaults, interface-only covariance transitions and unequal-signature semi-stubs remain explicit boundaries.

Generic binders retain analyzer-computed default type templates, including dependent and recursive bounds, aliases and captured owner types. Defaults remain separate from type identity, preserve capture-free substitution and are checked only when applied. Missing structural metadata stays explicit; dynamic calls apply them only after accepting the argument shape.

Invocation factories, constructor tear-offs, flags and argument getters reuse nominal storage and virtual calls. Argument collections preserve immutable shallow snapshots, copying order and the pinned SDK's typed empty identities. User implementations, inherited defaults and abstract/interface redeclarations retain ordinary dispatch; typed noSuchMethod forwarding uses a separate Invocation profile matching compiler-generated bodies.

Public Symbol literals and Symbol constructors reuse nominal storage and ordinary constant identity. Constant values canonicalize while runtime constructors remain fresh; equality, hashing, constructor tear-offs, object patterns and Symbol-typed toString calls preserve user implementations. Private source literals and their constant dependencies remain rejected because analyzer loses their library identity. Super hashCode reads now select Object identity hashing instead of recursively invoking an override.

Local late and late-final variables reuse captured cells and lexical initializer closures. Lazy reads, retries, single binding and exception paths preserve current captured values, generic environments and loop iteration identity. Nested named local functions use the closure plan for capture ownership when analyzer metadata omits their parent.

Instance late and late-final fields use receiver-bound lazy initializer bodies, preserving actual generic arguments, private/inherited storage, reentrant binding and exception identity. Constructors skip lazy initializers; explicit constructor writes still bind storage. Generic late-final setters retain covariant safety checks, with a documented difference from SDK 3.13.7.

Top-level and static mutable, final, late and late-final variables share ordinary accessor calls and lazy global storage. Initializers preserve first-read order, reentrant binding, retries after failures, writes made before or during initialization, and captured closure identity. Final commit checks retain RHS/type-check ordering and original exceptions.

Ordinary, enhanced and generic enums reuse class storage, constant identity and member dispatch. Values retain their index, name and actual type arguments; enum toString, factories, methods, operators and patterns share existing lowering. Class and enum static const declarations are validated without runtime storage. Enums with a user storage field named _name are rejected because pinned analyzer metadata overwrites that value.

Type literals, aliases and reified type parameters retain strict structural identity, equality and hashing, including nested constants and captured generic environments. Constant dependencies containing private Symbol literals are rejected before consuming analyzer-folded values, including folded scalars; the pinned analyzer loses private-library identity. Dynamic runtimeType is available only for represented concrete types; general static access and unmodeled SDK implementation types remain unsupported.

Dynamic for-in and collection spreads check the source protocol before traversal and cast elements in evaluation order. Map spreads requiring key/value checks use entries; compatible spreads use forEach. MapEntry values support ordinary and constant construction, generic key/value reads and lazy Map.entries views.

Constant List, Set, Map and ordinary user-class instances lower from analyzer-evaluated values. Nested constants, generic and inherited storage, defaults and constructor aliases retain canonical identity. Collection writes preserve reified type checks and immutable-operation failures; method addAll checks its source before traversal, separately from literal spreads.

List and Map patterns support ordered extraction, list rest slices, missing-key checks, nested destructuring and shared lazy reads across alternatives. Irrefutable shape failures throw StateError; contextual casts and assignment writes preserve Dart's failure ordering and atomicity.

IR distinguishes dynamic from Object? and preserves implicit checks for typed storage, arguments, returns, record and collection elements, and boolean contexts. Dynamic receiver/member/operator dispatch uses the shared runtime lookup. Statements and collection elements now share declaration and loop lowering; ordinary and dot-shorthand calls share their evaluation paths.

Generic top-level functions, static and instance methods, local functions and closures retain scoped type parameters, bounds and runtime type environments. Direct calls, function values and explicit or contextual instantiation preserve inferred type arguments, polymorphic recursion and virtual entry checks. Generic function types compare structurally up to binder renaming.

Generic constructor tear-offs support aliases with reordered, fixed or repeated type arguments and preserve distinct alias identity. Constant and default function values retain type arguments even when those arguments do not appear in their signature. Constant-pattern caches distinguish function and constructor instantiations.

Generic classes retain declaration type parameters and instantiated type arguments throughout IR. Constructors, factories and factory redirects substitute member signatures, superclass and interface types without copying function bodies. Runtime checks and constructor or method tear-offs preserve actual type arguments, bounds, covariance and type environments captured by closures.

Mutable typed List, Set and Map literals support conditional and loop elements, patterns, spreads and null-aware elements. Synchronous `for-in` uses the iterator protocol and preserves per-iteration captures, control flow and exceptions. Collection IR includes indexing, writes, length, add and addAll; the full SDK collection API remains unsupported.

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
