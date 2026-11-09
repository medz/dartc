import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';

import 'function_emitter.dart';

/// Converts a native scalar entry into the function's full-width Dart call.
final class NativeEntry<R extends Object>(final FunctionEmitter<R> emitter) {
  /// Emits the boundary conversions and reports the call to the Dart body.
  Uint8List generate(NativeSignature signature, void Function(Fixup) call) {
    final native = emitter.convention.classify(signature);
    Type fullWidth(Type type) => type.isFloating
        ? Double
        : type.integerLayout != null
        ? Int64
        : type;
    final body = emitter.convention.classify(
      NativeSignature(
        fullWidth(signature.result),
        signature.parameters.map(fullWidth),
      ),
    );
    final frame = emitter.convention.frameLayout(
      localBytes: 0,
      localAlignment: 8,
      savedRegisters: [],
      outgoingStackBytes: body.stackBytes,
    );
    emitter.prologue(frame);
    for (final (i, location) in native.parameters.indexed) {
      final type = signature.parameters[i];
      final integer = type.integerLayout;
      switch (location) {
        case RegisterArgument(:final register):
          if (integer != null && integer.bytes < 8) {
            emitter.extendInteger(
              register,
              bytes: integer.bytes,
              signed: integer.signed,
            );
          } else if (type == Float) {
            emitter.convertFloatToDouble(register, register);
          }
        case StackArgument(:final offset):
          final scratch = emitter.allocatableRegisters.lastWhere(
            (r) =>
                emitter.bank(r) ==
                    (type.isFloating
                        ? RegisterBank.floating
                        : RegisterBank.general) &&
                body.clobberedRegisters.contains(r) &&
                !native.parameters.any(
                  (p) => p is RegisterArgument<R> && p.register == r,
                ),
          );
          emitter.loadStack(
            scratch,
            frame.incomingStackOffset + offset,
            bytes: type.nativeSize,
            signed: integer?.signed ?? false,
          );
          if (type == Float) emitter.convertFloatToDouble(scratch, scratch);
          emitter.storeStack(
            scratch,
            (body.parameters[i] as StackArgument<R>).offset,
          );
      }
    }
    call(emitter.call());
    if (signature.result.integerLayout case final integer?
        when integer.bytes < 8) {
      emitter.extendInteger(
        native.result!,
        bytes: integer.bytes,
        signed: integer.signed,
      );
    } else if (signature.result == Float) {
      emitter.convertDoubleToFloat(native.result!, native.result!);
    }
    emitter.epilogue(frame);
    return emitter.finish();
  }
}
