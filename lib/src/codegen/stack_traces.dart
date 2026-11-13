import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'function_emitter.dart';
import 'heap_runtime.dart';

/// Passes the caller's machine frame to the checked Dart stack walker.
final class StackTraces(final HeapRuntime? runtime) {
  late final capture =
      runtime?.primitives.entries
          .singleWhere((entry) => entry.value == .captureStackTrace)
          .key ??
      FunctionTarget(null, 'capture', .stackTrace, []);

  Uint8List emit<R extends Object>(
    FunctionEmitter<R> emitter,
    void Function(Fixup, FunctionTarget) call,
    void Function(int, StackRoots) safepoint,
  ) {
    final layout = emitter.convention.classify(
      NativeSignature(Int64, [Int64, Int64]),
    );
    final arguments = layout.parameters
        .map((p) => (p as RegisterArgument<R>).register)
        .toList();
    final frame = emitter.convention.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: layout.stackBytes,
    );
    emitter.prologue(frame);
    emitter.stackAddress(arguments[0], frame.incomingStackOffset);
    emitter.loadStack(arguments[1], frame.returnAddressOffset);
    call(emitter.call(), runtime!.captureStackTrace);
    safepoint(
      emitter.position,
      StackRoots(frame.incomingStackOffset, frame.returnAddressOffset, []),
    );
    emitter.epilogue(frame);
    return emitter.finish();
  }
}
