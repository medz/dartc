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
  /// references cannot be exported as native pointers. Scalar constants and
  /// booleans can enter reference storage, and statically known scalar values
  /// can be unboxed. Boxing runtime integers and doubles remains unsupported.
  /// Type tests support null checks and results proved by static types;
  /// checks requiring runtime type metadata remain unsupported.
  /// Modules with references live across calls include read-only stack records
  /// keyed by relocated return addresses. These describe initialized reference
  /// slots and frame linkage; native entry wrappers terminate the frame walk.
  /// Updated root slots are reloaded after calls. [Construct] allocates objects,
  /// initializes their fields and calls their initializer; unreachable objects
  /// are reclaimed during allocation. Each synchronous native entry owns its
  /// heap until return, including entries made through a native callback.
  /// Escaping managed state, asynchronous execution and catchable allocation
  /// failures remain unsupported. An uncaught allocation failure releases the
  /// heap, reports to stderr and terminates the process with status 255.
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
