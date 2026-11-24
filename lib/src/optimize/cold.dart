import 'package:dartc/hir.dart';

/// The blocks of [order], which is in reverse postorder, after which only throws
/// come.
Set<HirBlock> coldBlocks(List<HirBlock> order) {
  final cold = <HirBlock>{};
  for (final block in order.reversed) {
    final end = block.terminator!, edges = end.edges;
    final isEnd = end is HirThrow || end is HirUnreachable;
    if (isEnd ||
        edges.isNotEmpty && edges.every((e) => cold.contains(e.target))) {
      cold.add(block);
    }
  }
  return cold;
}
