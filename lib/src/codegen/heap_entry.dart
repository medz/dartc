import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';

import 'function_emitter.dart';

/// Enters an activation-local heap or a module-owned heap with linked roots.
final class HeapEntry<R extends Object>(
  final FunctionEmitter<R> emitter,
  final FunctionTarget releaseFunction,
  final FunctionTarget isOutOfMemory,
  final FunctionTarget? runEvents,
  final void Function(Fixup) roots,
  final void Function(Fixup) error,
  final void Function(Fixup) uncaught,
  final void Function(Fixup, FunctionTarget) call,
  final void Function(int) safepoint, {
  final void Function(Fixup)? context,
  final void Function(Fixup)? globals,
}) {
  static const message = 'Unhandled exception:\nOut of Memory\n';
  static const uncaughtMessage =
      'Unhandled Dart exception at native boundary.\n';
  static const _result = RuntimeContext.size, _failure = _result + 8;
  static const _outOfMemory = _failure + 8;
  static const localBytes = _outOfMemory + 8;

  FrameLayout<R> frame(int outgoingStackBytes, {int extraBytes = 0}) =>
      emitter.convention.frameLayout(
        localBytes: localBytes + extraBytes,
        localAlignment: 8,
        savedRegisters: [emitter.heapRegister],
        outgoingStackBytes: outgoingStackBytes,
      );

  bool get persistent => context != null;

  void enter(FrameLayout<R> frame) {
    if (context case final address?) {
      emitter.address(emitter.heapRegister, address);
      emitter.loadMemory(
        emitter.failureRegister,
        emitter.heapRegister,
        offset: RuntimeContext.active,
        bytes: 8,
        signed: false,
      );
      emitter.storeStack(
        emitter.failureRegister,
        frame.localOffset + RuntimeContext.previousEntry,
      );
      emitter.stackAddress(emitter.failureRegister, frame.localOffset);
      emitter.storeMemory(
        emitter.failureRegister,
        emitter.heapRegister,
        offset: RuntimeContext.active,
        bytes: 8,
      );
      emitter.loadImmediate(emitter.failureRegister, 0);
      emitter.storeStack(
        emitter.failureRegister,
        frame.localOffset + RuntimeContext.suspendedSp,
      );
      emitter.storeStack(
        emitter.failureRegister,
        frame.localOffset + RuntimeContext.suspendedPc,
      );
      emitter.address(emitter.failureRegister, globals!);
      emitter.storeMemory(
        emitter.failureRegister,
        emitter.heapRegister,
        offset: RuntimeContext.globalRoots,
        bytes: 8,
      );
    } else {
      emitter.stackAddress(emitter.heapRegister, frame.localOffset);
      emitter.loadImmediate(emitter.failureRegister, 0);
      for (var offset = 0; offset < RuntimeContext.size; offset += 8) {
        emitter.storeMemory(
          emitter.failureRegister,
          emitter.heapRegister,
          offset: offset,
          bytes: 8,
        );
      }
    }
    emitter.address(emitter.failureRegister, roots);
    emitter.storeMemory(
      emitter.failureRegister,
      emitter.heapRegister,
      offset: RuntimeContext.maps,
      bytes: 8,
    );
    emitter.loadImmediate(emitter.failureRegister, 0);
  }

  /// Publishes a stack segment before native code can reenter the module.
  /// The caller resolves the returned address fixups to the exact return PC.
  static List<Fixup> park<T extends Object>(
    FunctionEmitter<T> emitter,
    T scratch,
  ) {
    if (scratch == emitter.failureRegister || scratch == emitter.heapRegister) {
      throw ArgumentError('Parked frame scratch aliases its context register.');
    }
    emitter.loadMemory(
      emitter.failureRegister,
      emitter.heapRegister,
      offset: RuntimeContext.active,
      bytes: 8,
      signed: false,
    );
    emitter.stackAddress(scratch, 0);
    emitter.storeMemory(
      scratch,
      emitter.failureRegister,
      offset: RuntimeContext.suspendedSp,
      bytes: 8,
    );
    final addresses = <Fixup>[];
    emitter.address(scratch, addresses.add);
    emitter.storeMemory(
      scratch,
      emitter.failureRegister,
      offset: RuntimeContext.suspendedPc,
      bytes: 8,
    );
    return addresses;
  }

  void leave(FrameLayout<R> frame, R? result, {bool release = false}) {
    if (result != null) emitter.storeStack(result, frame.localOffset + _result);
    emitter.storeStack(emitter.failureRegister, frame.localOffset + _failure);
    if (runEvents case final events?) {
      final idle = emitter.label(), finished = emitter.label();
      emitter.jumpIfZero(emitter.failureRegister, idle);
      emitter.jump(finished);
      emitter.bind(idle);
      if (persistent) {
        emitter.loadStack(
          emitter.failureRegister,
          frame.localOffset + RuntimeContext.previousEntry,
        );
        final outermost = emitter.label();
        emitter.jumpIfZero(emitter.failureRegister, outermost);
        emitter.jump(finished);
        emitter.bind(outermost);
      }
      final argument =
          emitter.convention
                  .classify(NativeSignature(Void, [Int64]))
                  .parameters
                  .single
              as RegisterArgument<R>;
      emitter.move(argument.register, emitter.heapRegister);
      call(emitter.call(), events);
      safepoint(emitter.position);
      emitter.storeStack(emitter.failureRegister, frame.localOffset + _failure);
      emitter.bind(finished);
    }
    final successful = emitter.label();
    emitter.loadStack(emitter.failureRegister, frame.localOffset + _failure);
    emitter.jumpIfZero(emitter.failureRegister, successful);
    final classification = emitter.convention.classify(
      NativeSignature(Int64, [Int64]),
    );
    final argument = classification.parameters.single as RegisterArgument<R>;
    emitter.move(argument.register, emitter.exceptionRegister);
    call(emitter.call(), isOutOfMemory);
    safepoint(emitter.position);
    emitter.storeStack(
      classification.resultRegister!,
      frame.localOffset + _outOfMemory,
    );
    emitter.bind(successful);

    void releaseHeap() {
      final location =
          emitter.convention
                  .classify(NativeSignature(Void, [Int64]))
                  .parameters
                  .single
              as RegisterArgument<R>;
      emitter.move(location.register, emitter.heapRegister);
      call(emitter.call(), releaseFunction);
      safepoint(emitter.position);
    }

    if (!persistent || release) {
      releaseHeap();
    } else {
      final retained = emitter.label();
      emitter.loadStack(emitter.failureRegister, frame.localOffset + _failure);
      emitter.jumpIfZero(emitter.failureRegister, retained);
      releaseHeap();
      emitter.bind(retained);
    }
    restoreCaller(frame);
    emitter.loadStack(emitter.failureRegister, frame.localOffset + _failure);
    final returned = emitter.label();
    emitter.jumpIfZero(emitter.failureRegister, returned);
    final thrown = emitter.label();
    final scratch = emitter.allocatableRegisters.firstWhere(
      (r) => emitter.bank(r) == .general && r != emitter.failureRegister,
    );
    emitter.loadStack(scratch, frame.localOffset + _outOfMemory);
    emitter.jumpIfZero(scratch, thrown);
    emitter.reportFailure(error, message.length);
    emitter.bind(thrown);
    emitter.reportFailure(uncaught, uncaughtMessage.length);
    emitter.bind(returned);
    if (result != null) emitter.loadStack(result, frame.localOffset + _result);
  }

  /// Unlinks this entry after callbacks and heap release have finished.
  void restoreCaller(FrameLayout<R> frame) {
    if (!persistent) return;
    emitter.loadStack(
      emitter.failureRegister,
      frame.localOffset + RuntimeContext.previousEntry,
    );
    emitter.storeMemory(
      emitter.failureRegister,
      emitter.heapRegister,
      offset: RuntimeContext.active,
      bytes: 8,
    );
  }
}
