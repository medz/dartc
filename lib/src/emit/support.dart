import 'package:dartc/lir.dart';

import 'unsupported.dart';

/// The calls that [block] makes.
Iterable<LirCall> callsOf(LirBlock block) => [
  ...block.instructions.whereType<LirCall>(),
  if (block.terminator case Invoke(:final call)) call,
];

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

  final allocate = module.signatures[allocateSymbol];
  final canAllocate = allocate == LirSignature([.i64], .ref);
  final thrower = module.signatures[throwSymbol];
  final canThrow = thrower == LirSignature([.ref, .ref]);
  for (final function in module.functions) {
    Never reject(Object what) => throw EmitUnsupported(function.name, '$what');
    for (final block in function.blocks) {
      if (!canAllocate && callsOf(block).any((call) => call is Alloc)) {
        reject('no function $allocateSymbol');
      }
      if (!canThrow && block.terminator is Throw) {
        reject('no function $throwSymbol');
      }
    }
  }
}
