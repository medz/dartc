import 'package:dartc/object.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

/// Generates relocatable native code from verified Dart IR.
abstract interface class CodeGenerator() {
  /// The explicit output platform, independent of the host.
  Target get target;

  /// Generates the selected definitions and exposes the declared native exports.
  ///
  /// Definitions must belong to [program] and include every directly called
  /// body or external declaration. [imports] binds external declarations to
  /// native signatures; [exports] exposes a subset of the supplied Dart bodies.
  /// The caller resolves native symbols and supplies their implementations when
  /// linking. Unsupported operations fail before an artifact is returned.
  /// Object constants require their class and inherited field definitions in
  /// [program]. Equal constants share storage within the generated module;
  /// references cannot be exported as native pointers. Integers, doubles and
  /// booleans can enter reference storage, and statically known scalar values
  /// can be unboxed. Computed numeric boxes participate in heap collection.
  /// Direct generic calls carry closed Type constants or forwarded function type
  /// arguments through the normal calling convention and root records.
  /// [ReifyType] reads those arguments; compound open types remain unsupported.
  /// Type literals are canonical within the module. Equality with a literal or
  /// reified parameter as receiver compares that identity; general Type member
  /// dispatch remains unsupported. Generic functions cannot be native exports.
  /// Modules with references live across calls include read-only stack records
  /// keyed by relocated return addresses. These describe initialized reference
  /// slots and frame linkage; native entry wrappers terminate the frame walk.
  /// Updated root slots are reloaded after calls. [Construct] allocates objects,
  /// initializes their fields and calls their initializer; unreachable objects
  /// are reclaimed during allocation. Constructor arguments use their declared
  /// representations; the instantiated class must have resolved type arguments.
  /// Generic field writes still require runtime checks and are unsupported.
  /// Each synchronous native entry owns its heap until return, including entries
  /// made through a native callback.
  /// [Throw] and [Invoke] support synchronous exception propagation and cleanup.
  /// Fresh throws capture the managed call sequence; rethrows retain the same
  /// exception and trace. Error subclasses retain their first throw's trace.
  /// [TypeTest] and typed catches inspect actual object types, including inherited
  /// interfaces and fully determined generic arguments. [TypeCast] and [NullCheck]
  /// preserve the value on success and throw TypeError on failure, following the
  /// same exception and cleanup paths. Checks requiring runtime type parameters,
  /// trace formatting and the Error.stackTrace getter remain unsupported.
  /// Exceptions cannot unwind foreign frames.
  /// Escaping managed state, asynchronous execution and catchable allocation
  /// failures remain unsupported. A failure escaping the native entry releases
  /// the heap, reports to stderr and terminates the process with status 255.
  ///
  /// [entryPoint] adds a process entry with the given link symbol. It
  /// calls a synchronous, parameterless Dart body and exits successfully after
  /// discarding its result. The body must belong to [definitions].
  ObjectModule generate(
    IrProgram program, {
    required Iterable<FunctionTarget> definitions,
    Map<FunctionTarget, NativeExport> exports = const {},
    Map<FunctionTarget, NativeImport> imports = const {},
    ({FunctionTarget function, String symbol})? entryPoint,
  });
}
