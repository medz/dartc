import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'system_calls.dart';

/// Bytes at the end of the stack for code that does not check it.
const _reservedBytes = 128 << 10;

/// The functions that code calls for allocations, throws and overflows, made
/// of what [module] supplies for them.
List<LirFunction> runtimeFunctions(
  HirModule module,
  Map<HirCallable, String> symbols,
) => [
  if (module.allocate case final allocate?)
    _allocate(
      symbols[allocate]!,
      module.outOfMemory == null ? null : symbols[module.outOfMemory],
    ),
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

/// Makes objects of the addresses that function [symbol] gives, and calls
/// [outOfMemory] where it gives none.
LirFunction _allocate(String symbol, String? outOfMemory) {
  final signature = LirSignature([.i64], .i64);
  final entry = LirBlock([.i64]);
  final address = entry.add(Call(symbol, signature, entry.parameters));
  final made = outOfMemory == null ? entry : LirBlock();
  final blocks = [entry];
  if (outOfMemory != null) {
    final full = LirBlock();
    entry.end(Branch(address, LirEdge(made), LirEdge(full)));
    full
      ..add(Call(outOfMemory, LirSignature([]), const []))
      ..end(Unreachable());
    blocks.addAll([made, full]);
  }
  made.end(Return(made.add(Convert(.intToRef, address))));
  return LirFunction(allocateSymbol, LirSignature([.i64], .ref), blocks);
}

/// Calls [symbol], which never returns.
LirFunction _forward(String name, LirSignature signature, String symbol) {
  final block = LirBlock(signature.parameters);
  block
    ..add(Call(symbol, signature, block.parameters))
    ..end(Unreachable());
  return LirFunction(name, signature, [block]);
}
