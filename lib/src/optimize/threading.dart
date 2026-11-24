import 'package:dartc/hir.dart';

/// Lets jumps in [blocks] go past blocks that only branch, where it is known
/// which way.
void threadJumps(List<HirBlock> blocks) {
  final outside = _usedOutside(blocks);
  bool canPass(HirBlock block) =>
      block.instructions.isEmpty &&
      block.terminator is HirBranch &&
      !block.parameters.any(outside.contains);
  for (final block in blocks) {
    final end = block.terminator!;
    if (end is! HirJump && end is! HirBranch) continue;
    final edges = [for (final edge in end.edges) _thread(edge, canPass)];
    if (edges.indexed.every((e) => identical(e.$2, end.edges[e.$1]))) continue;
    block.terminator = switch (end) {
      HirBranch(:final condition) => HirBranch(condition, edges[0], edges[1]),
      _ => HirJump(edges.single),
    };
  }
}

/// The parameters of [blocks] that other blocks use.
Set<HirParameter> _usedOutside(List<HirBlock> blocks) {
  final owners = {
    for (final block in blocks)
      for (final parameter in block.parameters) parameter: block,
  };
  final result = <HirParameter>{};
  for (final block in blocks) {
    void use(HirValue value) {
      if (value is HirParameter && owners[value] != block) result.add(value);
    }

    for (final instruction in block.instructions) {
      instruction.inputs.forEach(use);
    }
    final end = block.terminator!;
    end.inputs.forEach(use);
    for (final edge in end.edges) {
      edge.arguments.forEach(use);
    }
  }
  return result;
}

HirEdge _thread(HirEdge edge, bool Function(HirBlock block) canPass) {
  var current = edge;
  // Blocks that go round and round are not followed.
  for (var i = 0; i < 4; i++) {
    final target = current.target;
    if (!canPass(target)) break;
    final branch = target.terminator! as HirBranch;
    HirValue of(HirValue value) {
      final index = target.parameters.indexWhere((p) => identical(p, value));
      return index < 0 ? value : current.arguments[index];
    }

    final condition = of(branch.condition);
    if (condition is! HirConst) break;
    final next = condition.value == true ? branch.ifTrue : branch.ifFalse;
    current = HirEdge(next.target, next.arguments.map(of).toList());
  }
  return current;
}
