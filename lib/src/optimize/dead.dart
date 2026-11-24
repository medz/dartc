import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';

/// What of the code that starts at [entry] is needed.
List<HirBlock> removeDead(HirBlock entry) {
  final blocks = reversePostorder(
    entry,
    (block) => block.terminator!.edges.map((edge) => edge.target),
  );
  final needed = Set<HirValue>.identity();
  final stores = <HirValue, List<HirStore>>{};
  final pending = <HirValue>[];
  void need(HirValue value) {
    if (needed.add(value)) pending.add(value);
  }

  for (final block in blocks) {
    for (final instruction in block.instructions) {
      if (instruction is HirStore && _isFresh(instruction.object)) {
        (stores[instruction.object] ??= []).add(instruction);
      } else if (_hasEffect(instruction)) {
        need(instruction);
      }
    }
    final end = block.terminator!;
    end.inputs.forEach(need);
    for (final edge in end.edges) {
      edge.arguments.forEach(need);
    }
  }
  while (pending.isNotEmpty) {
    final value = pending.removeLast();
    if (value is HirInstruction) value.inputs.forEach(need);
    // What objects hold matters if they do.
    stores[value]?.forEach(need);
  }
  for (final block in blocks) {
    block.instructions.retainWhere(needed.contains);
  }
  return blocks;
}

/// Whether nothing else has [object] unless it is told.
bool _isFresh(HirValue object) => object is HirNew;

bool _hasEffect(HirInstruction instruction) => switch (instruction) {
  HirStore() || HirStoreElement() || HirStoreGlobal() || HirMachine() => true,
  HirCall() || HirVirtualCall() => true,
  _ => false,
};
