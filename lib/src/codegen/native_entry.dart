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
    final body = emitter.convention.classify(
      NativeSignature(
        signature.result.integerLayout == null ? signature.result : Int64,
        signature.parameters.map((t) => t.integerLayout == null ? t : Int64),
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
          }
        case StackArgument(:final offset):
          final scratch = emitter.allocatableRegisters.lastWhere(
            (r) =>
                emitter.bank(r) ==
                    (type == Double
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
    }
    emitter.epilogue(frame);
    return emitter.finish();
  }
}
