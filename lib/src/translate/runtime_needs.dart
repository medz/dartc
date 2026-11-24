import 'package:dartc/hir.dart';

import 'runtime_links.dart';

/// What a program needs of the runtime.
final class RuntimeNeeds(
  final RuntimeLinks _links,
  final HirFunction Function(String name) _runtime,
) {
  HirFunction? get allocate => _allocate;
  HirFunction? get raise => _raise;
  HirFunction? get outOfMemory => _outOfMemory;
  HirFunction? get stackOverflow => _stackOverflow;
  HirFunction? get uncaught => _uncaught;
  HirFunction? get eventLoop => _eventLoop;
  HirFunction? get callback => _callback;
  HirFunction? _allocate, _raise, _outOfMemory, _stackOverflow, _uncaught;
  HirFunction? get exitCode => _exitCode;
  HirFunction? _eventLoop, _callback, _exitCode;

  /// Says that it creates objects.
  void addAllocation() => _allocate ??= _runtime('allocate');

  /// Says that C calls it.
  void addCallbacks() => _callback ??= _runtime('runCallback');

  /// Says that it lets work be done later.
  void addEvents() => _eventLoop ??= _runtime('runEventLoop');

  /// Says that it sets the code that it ends with.
  void addExitCode() => _exitCode ??= _runtime('exitCode');

  /// Adds what [functions], which are those known so far, need.
  void update(Iterable<HirFunction> functions) {
    if (!functions.any(_canThrow)) return;
    _stackOverflow ??= _links.exhaustion('StackOverflowError');
    _raise ??= _runtime('raise');
    _uncaught ??= _runtime('reportUncaught');
    if (_allocate == null) return;
    _outOfMemory ??= _links.exhaustion('OutOfMemoryError');
  }

  /// Whether [function] throws, or calls what may use up the stack.
  static bool _canThrow(HirFunction function) => function.blocks.any(
    (block) =>
        block.terminator is HirInvoke ||
        block.terminator is HirThrow ||
        block.instructions.any((instruction) => instruction is HirCalling),
  );
}
