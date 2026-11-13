import 'package:dartc/object.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/target.dart';

import 'heap_runtime.dart';

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
  /// Generated support functions and their source dependencies are resolved
  /// before native instruction selection.
  /// [runtime] supplies the ordinary Dart heap algorithms. Managed allocation
  /// requires it; unused bodies are omitted. Its transitive dependencies must
  /// be present in [program], with the contracts specified by [HeapRuntime].
  /// Dart void results retain their actual values; native Void calls produce
  /// null when their results are observed from Dart.
  ///
  /// [imports] binds external declarations to native signatures; [exports]
  /// exposes supplied Dart bodies. The caller supplies native implementations
  /// when linking. Managed values cannot cross native or module boundaries.
  /// [nativeSymbols] binds address operands to undecorated native names; data
  /// and function pointers use the linker's address relocations.
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
  /// must belong to [definitions], be synchronous or async, and accept either
  /// no parameters or two integers carrying OS argc and argv. The entry discards
  /// the result, drains events and reads [HeapRuntime.processExitCode] when
  /// supplied in [definitions], otherwise using zero, before releasing the heap.
  /// It emits no
  /// finalizer section; executable linking rejects inputs containing one.
  ObjectModule generate(
    IrProgram program, {
    required Iterable<FunctionTarget> definitions,
    Map<FunctionTarget, NativeExport> exports = const {},
    Map<FunctionTarget, NativeImport> imports = const {},
    Map<NativeReference, String> nativeSymbols = const {},
    ({FunctionTarget function, String symbol})? entryPoint,
    HeapRuntime? runtime,
  });
}
