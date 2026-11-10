import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';

import 'function_emitter.dart';
import 'heap_entry.dart';

/// Converts between native scalar signatures and full-width Dart calls.
final class NativeAdapter<R extends Object>(final FunctionEmitter<R> emitter) {
  /// Emits an incoming or outgoing native boundary and reports its direct call.
  Uint8List generate(
    NativeSignature signature,
    void Function(Fixup, int, FrameLayout<R>) call, {
    required bool intoDart,
    HeapEntry<R>? heap,
    void Function(Fixup, int)? codeAddress,
  }) {
    final native = emitter.convention.classify(signature);
    NativeTypeRef fullWidth(NativeTypeRef type) => type.isFloating
        ? NativeScalarType(Double)
        : type.integerLayout != null
        ? NativeScalarType(Int64)
        : type;
    final body = emitter.convention.classify(
      NativeSignature.types(
        fullWidth(signature.result),
        signature.parameters.map(fullWidth),
      ),
    );
    final (source, destination) = intoDart ? (native, body) : (body, native);
    final frame = intoDart && heap != null
        ? heap.frame(destination.stackBytes)
        : emitter.convention.frameLayout(
            localBytes: 0,
            localAlignment: 8,
            savedRegisters: [],
            outgoingStackBytes: destination.stackBytes,
          );
    emitter.prologue(frame);
    if (intoDart) heap?.enter(frame);
    for (final (i, location) in source.parameters.indexed) {
      final type = signature.parameters[i];
      final integer = type.integerLayout;
      switch (location) {
        case RegisterArgument(:final register):
          convert(register, type, intoDart: intoDart);
        case StackArgument(:final offset):
          final scratch = emitter.allocatableRegisters.lastWhere(
            (r) =>
                emitter.bank(r) ==
                    (type.isFloating
                        ? RegisterBank.floating
                        : RegisterBank.general) &&
                destination.clobberedRegisters.contains(r) &&
                !source.parameters.any(
                  (p) => p is RegisterArgument<R> && p.register == r,
                ),
          );
          emitter.loadStack(
            scratch,
            frame.incomingStackOffset + offset,
            bytes: intoDart ? type.nativeSize : 8,
            signed: intoDart && (integer?.signed ?? false),
          );
          if (type.isSinglePrecision) {
            convert(scratch, type, intoDart: intoDart);
          }
          emitter.storeStack(
            scratch,
            (destination.parameters[i] as StackArgument<R>).offset,
            bytes: intoDart ? 8 : type.nativeSize,
          );
      }
    }
    final parked = !intoDart && heap?.persistent == true
        ? HeapEntry.park(
            emitter,
            emitter.allocatableRegisters.lastWhere(
              (r) =>
                  emitter.bank(r) == .general &&
                  r != emitter.failureRegister &&
                  destination.clobberedRegisters.contains(r) &&
                  !destination.parameters.any(
                    (p) => p is RegisterArgument<R> && p.register == r,
                  ),
            ),
          )
        : const <Fixup>[];
    final fixup = emitter.call();
    call(fixup, emitter.position, frame);
    for (final address in parked) {
      codeAddress!(address, emitter.position);
    }
    if (intoDart) heap?.leave(frame, destination.result);
    if (destination.result case final result?) {
      convert(result, signature.result, intoDart: !intoDart);
    }
    if (!intoDart && heap != null) {
      emitter.loadImmediate(emitter.failureRegister, 0);
    }
    emitter.epilogue(frame);
    return emitter.finish();
  }

  /// Converts one scalar in place at a native call boundary.
  void convert(R register, NativeTypeRef type, {required bool intoDart}) {
    if (type.integerLayout case final integer? when integer.bytes < 8) {
      emitter.extendInteger(
        register,
        bytes: integer.bytes,
        signed: integer.signed,
      );
    } else if (type.isSinglePrecision) {
      if (intoDart) {
        emitter.convertFloatToDouble(register, register);
      } else {
        emitter.convertDoubleToFloat(register, register);
      }
    }
  }
}
