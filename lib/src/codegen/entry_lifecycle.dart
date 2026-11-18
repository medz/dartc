import 'dart:ffi' show Int64;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'heap_runtime.dart';

/// Builds ordinary entry bodies with caller-owned roots and explicit cleanup.
///
/// Native conversion precedes these bodies. Results have the native bridge's
/// scalar representation, and callbacks convert body failures before draining.
/// All runtime calls remain in the program being analyzed and rewritten.
final class EntryLifecycle(
  final HeapRuntime runtime, {
  required Value Function(Block) globalRoots,

  /// Shared module context; null selects fresh activation-local storage.
  final NativeData? context,
}) {
  final Value Function(Block) _globalRoots = globalRoots;
  final _functions = <IrFunction>[];
  final _outOfMemory = NativeData(
    'Unhandled exception:\nOut of Memory\n'.codeUnits,
    writable: false,
  );
  final _uncaught = NativeData(
    'Unhandled Dart exception at native boundary.\n'.codeUnits,
    writable: false,
  );

  /// Generated bodies, which must join the same program as their callees.
  Iterable<IrFunction> get functions => _functions;

  /// Wraps a converted native body, or a process body whose result is discarded.
  FunctionTarget wrap(
    FunctionTarget body, {
    bool process = false,
    NativeCallbackTarget? callback,
  }) {
    if (process && callback != null) {
      throw ArgumentError('A process entry cannot be a native callback.');
    }
    return _build(body, process: process, callback: callback);
  }

  /// Releases a persistent module without scheduling new event delivery.
  FunctionTarget close() {
    if (context == null) {
      throw StateError('Module cleanup requires module-owned context storage.');
    }
    return _build(null);
  }

  FunctionTarget _build(
    FunctionTarget? body, {
    bool process = false,
    NativeCallbackTarget? callback,
  }) {
    final cleanup = body == null;
    final persistent = context != null && !process;
    final resultType = process
        ? ValueType.integer
        : body?.returnType ?? .voidType;
    final target = FunctionTarget(
      null,
      cleanup ? 'moduleRelease' : 'entry${_functions.length}',
      resultType,
      body?.parameterTypes ?? const [],
    );
    final blocks = <Block>[];
    Block block([Iterable<ValueType> parameters = const []]) {
      final value = Block(parameters);
      blocks.add(value);
      return value;
    }

    final entry = block(target.parameterTypes);
    final address = entry.emit(
      context != null
          ? NativeDataAddress(context!)
          : NativeLocalStorage(
              NativeArrayType(.of(Int64), RuntimeContext.size ~/ 8),
              zeroInitialize: true,
            ),
    );
    // Distinct declarations provide nonoverlapping storage for every live entry.
    final record = entry.emit(
      NativeLocalStorage(
        NativeArrayType(.of(Int64), RuntimeContext.entrySize ~/ 8),
      ),
    );
    entry.emit(BindNativeContext(address));
    var start = entry;
    if (cleanup) {
      // Unloading an active module would release the caller's live heap.
      final idle = block(), invalid = block();
      final active = entry.emit(
        LoadNative(
          entry.emit(
            IntBinary(
              .add,
              address,
              const Constant.integer(RuntimeContext.active),
            ),
          ),
          NativeScalarType(Int64),
        ),
      );
      entry.finish(
        Branch(
          entry.emit(Equals(active, const Constant.integer(0))),
          Jump(idle),
          Jump(invalid),
        ),
      );
      final fail = runtime.primitives.entries
          .singleWhere((entry) => entry.value == .fail)
          .key;
      invalid.finish(Unreachable(invalid.emit(DirectCall(fail, []))));
      start = idle;
    }
    start.emit(
      DirectCall(runtime.linkEntry, [
        address,
        record,
        start.emit(StackMapAddress()),
        _globalRoots(start),
      ]),
    );

    final failed = block([.object]);
    final fatal = block([.boolean]);
    final finished = block(
      resultType == .voidType || resultType == .never ? [] : [resultType],
    );

    void unlink(Block current) {
      current.emit(DirectCall(runtime.unlinkEntry, [address, record]));
    }

    // Failure classification happens while its object is still live. A cleanup
    // failure overrides the pending outcome without dereferencing freed memory.
    final classification = failed.emit(
      DirectCall(runtime.isOutOfMemory, [failed.parameters.single]),
    );
    final releasedFailure = block([.boolean]);
    final releaseFailed = block();
    failed.finish(
      Invoke(
        DirectCall(runtime.release, [address]),
        onReturn: Jump(releasedFailure, [classification]),
        onThrow: Jump(releaseFailed),
      ),
    );
    unlink(releasedFailure);
    releasedFailure.finish(Jump(fatal, releasedFailure.parameters));
    unlink(releaseFailed);
    releaseFailed.finish(Jump(fatal, [const Constant.boolean(false)]));

    final oom = block(), uncaught = block();
    fatal.finish(Branch(fatal.parameters.single, Jump(oom), Jump(uncaught)));
    final write = runtime.primitives.entries
        .singleWhere((entry) => entry.value == .writeBytes)
        .key;
    final exit = runtime.primitives.entries
        .singleWhere((entry) => entry.value == .exitProcess)
        .key;
    for (final (current, message) in [
      (oom, _outOfMemory),
      (uncaught, _uncaught),
    ]) {
      current.emit(
        DirectCall(write, [
          const Constant.integer(2),
          current.emit(NativeDataAddress(message)),
          Constant.integer(message.bytes.length),
        ]),
      );
      current.finish(
        Unreachable(
          current.emit(DirectCall(exit, [const Constant.integer(255)])),
        ),
      );
    }

    final returned = block(
      body == null || body.returnType == .voidType || body.returnType == .never
          ? []
          : [body.returnType],
    );
    if (body == null) {
      start.finish(Jump(returned));
    } else {
      final call = DirectCall(body, entry.parameters);
      final callbackFailure = callback == null ? null : block();
      start.finish(
        Invoke(
          call,
          onReturn: body.returnType == .never
              ? null
              : Jump(returned, body.returnType == .voidType ? [] : [call]),
          onThrow: callbackFailure == null
              ? Jump(failed, [UnwindValue.exception])
              : Jump(callbackFailure),
        ),
      );
      if (callbackFailure != null) {
        final nativeResult = callback!.signature.result;
        if (nativeResult is NativeCompoundType) {
          final zero = callbackFailure.emit(
            NativeLocalStorage(nativeResult, zeroInitialize: true),
          );
          callbackFailure.emit(
            CopyNative(entry.parameters.first, zero, nativeResult),
          );
        }
        final fallback = callback.exceptionalReturn;
        callbackFailure.finish(
          Jump(returned, [
            if (returned.parameters.isNotEmpty)
              fallback is ScalarConstant ? fallback : const Constant.integer(0),
          ]),
        );
      }
    }

    final completed = block();
    final drained = block();
    if (cleanup) {
      returned.finish(Jump(completed));
    } else {
      final drain = block();
      final previous = returned.emit(
        LoadNative(record, NativeScalarType(Int64)),
      );
      returned.finish(
        Branch(
          returned.emit(Equals(previous, const Constant.integer(0))),
          Jump(drain),
          Jump(drained),
        ),
      );
      drain.finish(
        Invoke(
          DirectCall(runtime.runEvents, [address, Constant.boolean(process)]),
          onReturn: Jump(drained),
          onThrow: Jump(failed, [UnwindValue.exception]),
        ),
      );
      if (runtime.processExitCode case final status? when process) {
        final call = DirectCall(status, []);
        final statusRead = block([.integer]);
        drained.finish(
          Invoke(
            call,
            onReturn: Jump(statusRead, [call]),
            onThrow: Jump(failed, [UnwindValue.exception]),
          ),
        );
        statusRead.finish(Jump(finished, statusRead.parameters));
      } else {
        drained.finish(
          Jump(
            finished,
            process ? [const Constant.integer(0)] : returned.parameters,
          ),
        );
      }
    }

    if (cleanup) {
      // No normal result is live, and no event loop is entered during unload.
      completed.finish(
        Invoke(
          DirectCall(runtime.release, [address]),
          onReturn: Jump(finished),
          onThrow: Jump(releaseFailed),
        ),
      );
      unlink(finished);
      finished.finish(const Return());
    } else if (!persistent) {
      final releasing = block(finished.parameters.map((p) => p.type));
      final released = block(finished.parameters.map((p) => p.type));
      final previous = finished.emit(
        LoadNative(record, NativeScalarType(Int64)),
      );
      finished.finish(
        Branch(
          finished.emit(Equals(previous, const Constant.integer(0))),
          Jump(releasing, finished.parameters),
          Jump(released, finished.parameters),
        ),
      );
      releasing.finish(
        Invoke(
          DirectCall(runtime.release, [address]),
          onReturn: Jump(released, releasing.parameters),
          onThrow: Jump(releaseFailed),
        ),
      );
      unlink(released);
      released.finish(Return(released.parameters.firstOrNull));
    } else {
      unlink(finished);
      finished.finish(Return(finished.parameters.firstOrNull));
    }
    // Unreachable construction blocks have no behavior and no valid terminator.
    final reachable = <Block>{};
    void visit(Block current) {
      if (!reachable.add(current)) return;
      for (final edge in current.end.successors) {
        visit(edge.target);
      }
    }

    visit(entry);
    final function = IrFunction(target, blocks.where(reachable.contains));
    _functions.add(function);
    return target;
  }
}
