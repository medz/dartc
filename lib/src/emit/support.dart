import 'package:dartc/lir.dart';

import 'code.dart';

/// Throws [EmitUnsupported] for anything code generation cannot translate.
void checkSupported(LirModule module) {
  for (final external in module.externals) {
    final LirSignature(:parameters, :result) = external.signature;
    for (final type in [...parameters, ?result]) {
      if (type == .f64 || type == .ref) {
        throw EmitUnsupported(external.name, '$type');
      }
    }
  }
  for (final data in module.data) {
    throw EmitUnsupported(data.name, 'data');
  }
  for (final function in module.functions) {
    Never reject(Object what) => throw EmitUnsupported(function.name, '$what');
    for (final block in function.blocks) {
      for (final value in [...block.parameters, ...block.instructions]) {
        if (value.type == .f64 || value.type == .ref) reject(value.type!);
      }
      for (final instruction in block.instructions) {
        switch (instruction) {
          case Load() || Store() || Alloc():
            reject(instruction.runtimeType);
          default:
            break;
        }
      }
      if (block.terminator case Throw() || Invoke()) {
        reject(block.terminator!.runtimeType);
      }
    }
  }
}
