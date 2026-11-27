import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'system_calls.dart';

/// Bytes at the end of the stack for code that does not check it.
const _reservedBytes = 128 << 10;

/// The functions that code calls for throws and overflows, made of what
/// [module] supplies for them. Allocations call that of [module] itself.
List<LirFunction> runtimeFunctions(
  HirModule module,
  Map<HirCallable, String> symbols,
) => [
  if (module.raise case final raise?)
    _forward(throwSymbol, LirSignature([.ref, .ref]), symbols[raise]!),
  if (module.stackOverflow case final overflow?)
    _forward(stackOverflowSymbol, LirSignature([]), symbols[overflow]!),
];

/// What checks of the stack read.
LirStatic stackLimit() => LirStatic(
  stackLimitSymbol,
  List.filled(8, 0),
  writable: true,
  isolated: true,
);

/// Finds out how far the stack may reach.
void setStackLimit(LirBlock block, SystemCalls system) {
  final reserved = block.add(ConstInt(_reservedBytes));
  final start = system.stackStart(block);
  block.add(
    Store(
      .i64,
      block.add(StaticObject(stackLimitSymbol)),
      block.add(IntBinary(.add, start, reserved)),
    ),
  );
}

/// Calls [symbol], which never returns.
LirFunction _forward(String name, LirSignature signature, String symbol) {
  final block = LirBlock(signature.parameters);
  block
    ..add(Call(symbol, signature, block.parameters))
    ..end(Unreachable());
  return LirFunction(name, signature, [block]);
}
