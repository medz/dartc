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
  /// body or external declaration, including implementations selected by virtual
  /// calls. [IrProgram.reachableFrom] selects these for a closed program. Managed
  /// receivers from other modules are not supported. [imports] binds external declarations to
  /// native signatures; [exports] exposes a subset of the supplied Dart bodies.
  /// The caller resolves native symbols and supplies their implementations when
  /// linking. Unsupported operations fail before an artifact is returned.
  /// Object constants require their class and inherited field definitions in
  /// [program]. Equal constants share storage within the generated module;
  /// references cannot be exported as native pointers. Integers, doubles and
  /// booleans can enter reference storage, and statically known scalar values
  /// can be unboxed. Computed numeric boxes participate in heap collection.
  /// String constants retain their UTF-16 code units and canonical identity in
  /// immutable module storage. String operations remain unsupported.
  /// Integer truncating division, modulo and remainder retain signed 64-bit
  /// behavior, including overflow, and throw IntegerDivisionByZeroException
  /// for a zero divisor through normal exception edges.
  /// Floating and mixed truncating division divides as double, then applies
  /// [NumericToInt]; boxed integer pairs keep exact integer division.
  /// Integer shifts retain the complete count: counts of 64 or more saturate
  /// arithmetic right shifts and zero the other results. Negative counts throw
  /// ArgumentError using its constructor and inherited class bodies supplied in
  /// [program]. Generated dependencies use the same member selection as user code.
  /// [NumericToInt] preserves integer operands and rounds floating operands in
  /// the requested direction, clamping finite overflow to signed 64-bit bounds.
  /// Non-finite inputs require the supplied UnsupportedError constructor body
  /// and throw through normal exception edges. Boxed num operands retain their
  /// actual integer or double representation. [NumericRoundToDouble] rounds to
  /// integral doubles without saturation, preserving non-finite values and
  /// negative zero. It does not require an exception constructor.
  /// Direct generic calls carry reified type arguments through the normal
  /// calling convention and root records. [ReifyType] reads or combines class and function
  /// type arguments into nullable, nominal, FutureOr, function and record types.
  /// Type literals are canonical within the module. Built-in Type equality
  /// compares normalized structures; user Type implementations retain their
  /// equality override or inherited identity comparison, including the null rule.
  /// Object runtime types survive collection and preserve actual generic arguments.
  /// [ObjectRuntimeType] selects user overrides unless a super call chose the
  /// built-in getter. Generic function
  /// bounds use the actual enclosing function arguments, including nested and
  /// chained binders. Class environments follow the actual receiver's inherited
  /// arguments; factories receive the requested owner type. Built-in Type hashing
  /// and formatting remain unsupported. Generic functions cannot be native exports.
  /// Ordinary class member calls select the actual implementation, bind its
  /// defaults and check parameters and generic bounds before entering the body.
  /// Inherited and mixin implementations retain super calls. Scalar results are
  /// converted to the caller's representation. Other Object member dispatch, Never
  /// parameters and value-returning views of void implementations remain unsupported.
  /// Modules with references live across calls include read-only stack records
  /// keyed by relocated return addresses. These describe initialized reference
  /// slots and frame linkage; native entry wrappers terminate the frame walk.
  /// Updated root slots are reloaded after calls. [Construct] allocates objects,
  /// initializes their fields and calls their initializer; unreachable objects
  /// are reclaimed during allocation. Constructor arguments use their declared
  /// representations and runtime type arguments. Generic field writes check the
  /// actual receiver's field type before modifying storage; failure throws TypeError.
  /// Each synchronous native entry owns its heap until return, including entries
  /// made through a native callback.
  /// [Throw] and [Invoke] support synchronous exception propagation and cleanup.
  /// Fresh throws capture the managed call sequence; rethrows retain the same
  /// exception and trace. Error subclasses retain their first throw's trace.
  /// [TypeTest] and typed catches inspect actual object types, including inherited
  /// interfaces and fully determined generic arguments. [TypeCast] and [NullCheck]
  /// preserve the value on success and throw TypeError on failure, following the
  /// same exception and cleanup paths. Trace formatting and the Error.stackTrace
  /// getter remain unsupported.
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
