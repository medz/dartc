import 'package:dartc/lir.dart';

import 'arm64/convention.dart';
import 'code.dart';

/// Throws [EmitUnsupported] for anything code generation cannot translate.
void checkSupported(LirModule module) {
  for (final external in module.externals) {
    final LirSignature(:parameters, :result) = external.signature;
    for (final type in [...parameters, ?result]) {
      if (type == .ref) {
        throw EmitUnsupported(external.name, '$type');
      }
    }
  }
  for (final data in module.data) {
    if (data.writable) throw EmitUnsupported(data.name, 'writable data');
  }
  final allocate = module.signatures[allocateSymbol];
  final canAllocate = allocate == LirSignature([.i64], .ref);
  for (final function in module.functions) {
    Never reject(Object what) => throw EmitUnsupported(function.name, '$what');
    for (final block in function.blocks) {
      if (!canAllocate && block.instructions.any((i) => i is Alloc)) {
        reject('no function $allocateSymbol');
      }
      if (block.terminator case Throw() || Invoke()) {
        reject(block.terminator!.runtimeType);
      }
    }
  }
}
