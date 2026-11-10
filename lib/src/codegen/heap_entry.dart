import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'function_emitter.dart';
import 'heap_functions.dart';

/// Owns the heap for a synchronous native activation with no escaping objects.
// shortcut: activation-local heap, replace before enabling escaping managed state.
final class HeapEntry<R extends Object>(
  final FunctionEmitter<R> emitter,
  final HeapFunctions functions,
  final void Function(Fixup) roots,
  final void Function(Fixup) error,
  final void Function(Fixup, FunctionTarget) call,
) {
  static const message = 'Unhandled exception:\nOut of Memory\n';
  static const _result = HeapFunctions.contextBytes, _failure = _result + 8;

  FrameLayout<R> frame(int outgoingStackBytes) =>
      emitter.convention.frameLayout(
        localBytes: _failure + 8,
        localAlignment: 8,
        savedRegisters: [emitter.heapRegister],
        outgoingStackBytes: outgoingStackBytes,
      );

  void enter(FrameLayout<R> frame) {
    emitter.stackAddress(emitter.heapRegister, frame.localOffset);
    emitter.loadImmediate(emitter.failureRegister, 0);
    for (var offset = 0; offset < HeapFunctions.contextBytes; offset += 8) {
      emitter.storeMemory(
        emitter.failureRegister,
        emitter.heapRegister,
        offset: offset,
        bytes: 8,
      );
    }
    emitter.address(emitter.failureRegister, roots);
    emitter.storeMemory(
      emitter.failureRegister,
      emitter.heapRegister,
      offset: HeapFunctions.maps,
      bytes: 8,
    );
  }

  void leave(FrameLayout<R> frame, R? result) {
    if (result != null) emitter.storeStack(result, frame.localOffset + _result);
    emitter.storeStack(emitter.failureRegister, frame.localOffset + _failure);
    final location =
        emitter.convention
                .classify(NativeSignature(Void, [Int64]))
                .parameters
                .single
            as RegisterArgument<R>;
    emitter.move(location.register, emitter.heapRegister);
    call(emitter.call(), functions.release);
    emitter.loadStack(emitter.failureRegister, frame.localOffset + _failure);
    final returned = emitter.label();
    emitter.jumpIfZero(emitter.failureRegister, returned);
    emitter.outOfMemory(error, message.length);
    emitter.bind(returned);
    if (result != null) emitter.loadStack(result, frame.localOffset + _result);
  }
}
