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
  /// [definitions] must belong to [program] and include every directly called
  /// body or external declaration and every selected virtual implementation.
  /// [IrProgram.reachableFrom] selects these for a closed program. Required class
  /// definitions include inherited fields and SDK error constructors used by
  /// generated checks. Unsupported operations fail before returning an artifact.
  ///
  /// [imports] binds external declarations to native signatures; [exports]
  /// exposes supplied Dart bodies. The caller supplies native implementations
  /// when linking. Managed values cannot cross native or module boundaries.
  ///
  /// Constants have module-local canonical identity. Objects, closures and shared
  /// cells use traced storage. Reference globals retain a heap across native
  /// calls; otherwise each activation releases its heap on return. Same-module,
  /// single-threaded synchronous native reentry preserves suspended roots.
  /// Persistent heaps require dartc linking for shared-library unload cleanup;
  /// external linking of raw Mach-O objects does not guarantee cleanup.
  ///
  /// Exceptions propagate through Dart frames. A failure escaping a native entry
  /// releases the heap, reports to stderr and exits with status 255. Concurrent
  /// or cross-thread entry and unwinding through foreign frames are unsupported.
  /// Language and library support is tracked in the project's specs directory.
  ///
  /// [entryPoint] adds a process entry with the given link symbol. Its function
  /// must belong to [definitions] and be synchronous and parameterless. The entry
  /// discards the result, releases the heap and exits successfully. It emits no
  /// finalizer section; executable linking rejects inputs containing one.
  ObjectModule generate(
    IrProgram program, {
    required Iterable<FunctionTarget> definitions,
    Map<FunctionTarget, NativeExport> exports = const {},
    Map<FunctionTarget, NativeImport> imports = const {},
    ({FunctionTarget function, String symbol})? entryPoint,
  });
}
