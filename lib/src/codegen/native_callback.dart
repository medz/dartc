import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'function_emitter.dart';

/// The machine entry protocol for a static, thread-bound native callback.
final class NativeCallback<R extends Object>(
  final FunctionEmitter<R> emitter,
  final NativeCallbackAddress definition,
  final void Function(Fixup) owner,
) {
  void checkThread({bool bind = false}) {
    final current = emitter.currentThread();
    final clobbered = emitter.convention
        .classify(NativeSignature(Int64, []))
        .clobberedRegisters;
    final scratch = emitter.allocatableRegisters.where(
      (r) =>
          emitter.bank(r) == .general &&
          r != current &&
          r != emitter.failureRegister &&
          r != emitter.heapRegister &&
          clobbered.contains(r),
    );
    final address = scratch.first, previous = scratch.skip(1).first;
    emitter.address(address, owner);
    emitter.loadMemory(previous, address, bytes: 8, signed: false);
    final valid = emitter.label();
    if (bind) emitter.jumpIfZero(previous, valid);
    emitter.comparison(.notEqual).emit(previous, previous, current);
    emitter.jumpIfZero(previous, valid);
    emitter.abort(70);
    emitter.bind(valid);
    if (bind) emitter.storeMemory(current, address, bytes: 8);
  }

  Uint8List address(void Function(Fixup) entry) {
    checkThread(bind: true);
    final result = emitter.convention
        .classify(NativeSignature(Int64, []))
        .resultRegister!;
    emitter.address(result, entry);
    emitter.loadImmediate(emitter.failureRegister, 0);
    emitter.ret();
    return emitter.finish();
  }
}
