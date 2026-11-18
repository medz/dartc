import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/assembler.dart';
import 'package:dartc/interop.dart';

import 'function_emitter.dart';
import 'heap_runtime.dart';

/// Emits the machine services that cannot be expressed by ordinary Dart code.
final class MemoryFunction<R extends Object>(
  final MemoryPrimitive primitive,
  final FunctionEmitter<R> emitter,
) {
  Uint8List generate(
    void Function(Fixup) systemClock,
    void Function(Fixup) callbackTemplate,
  ) {
    switch (primitive) {
      case .flushInstructions:
        return emitter.flushInstructions();
      case .map:
        return emitter.mapMemory();
      case .unmap:
        return emitter.unmapMemory();
      case .writeBytes:
        return emitter.writeBytes();
      case .entropy:
        return emitter.entropy();
      case .clock:
        return emitter.clock(systemClock);
      case .sleep:
        return emitter.sleep();
      case .fail:
        emitter.abort(71);
        return emitter.finish();
      case .exitProcess:
        emitter.exitProcess();
        return emitter.finish();
      case .currentThread:
        emitter.currentThread();
      case .callbackTemplate:
        final result = emitter.convention
            .classify(NativeSignature(Int64, []))
            .resultRegister!;
        emitter.address(result, callbackTemplate);
    }
    emitter.loadImmediate(emitter.failureRegister, 0);
    emitter.ret();
    return emitter.finish();
  }
}
