import 'package:dartc/ir.dart';

/// Checks semantic binding before physical zeroed storage can hide an unsafe read.
void checkCellInitialization(IrFunction function) {
  bool isCell(Value value) =>
      value.type is CellType && !(value.type as CellType).isLate;
  Iterable<Instruction> operations(Block block) => [
    ...block.instructions,
    if (block.end case Invoke(:final operation)) operation,
  ];
  final cells = <Value>{
    for (final block in function.blocks) ...[
      ...block.parameters.where(isCell),
      ...operations(block).where(isCell),
    ],
  };
  if (cells.isEmpty) return;
  final predecessors = {
    for (final block in function.blocks) block: <(Block, Jump, bool)>[],
  };
  for (final block in function.blocks) {
    for (final edge in block.successors) {
      predecessors[edge.target]!.add((
        block,
        edge,
        block.end is Invoke && identical(edge, (block.end as Invoke).onThrow),
      ));
    }
  }
  final origins = {
    for (final cell in cells)
      cell:
          cell is NewCell ||
              cell is CopyCell ||
              function.entry.parameters.contains(cell)
          ? <Value>{cell}
          : <Value>{},
  };
  bool changed;
  do {
    changed = false;
    for (final block in function.blocks) {
      for (final (_, edge, _) in predecessors[block]!) {
        for (final (i, parameter) in block.parameters.indexed) {
          if (!isCell(parameter)) continue;
          final known = origins[parameter]!;
          final length = known.length;
          known.addAll(origins[edge.arguments[i]] ?? const <Value>{});
          changed |= known.length != length;
        }
      }
    }
  } while (changed);

  bool ready(Value cell, Set<Value> initialized) =>
      initialized.contains(cell) ||
      origins[cell]!.isNotEmpty && origins[cell]!.every(initialized.contains);
  final initialized = {
    for (final block in function.blocks)
      block: (normal: cells.toSet(), exceptional: cells.toSet()),
  };
  ({Set<Value> normal, Set<Value> exceptional}) after(
    Block block, {
    bool check = false,
  }) {
    final bound = block == function.entry
        ? <Value>{...function.entry.parameters.where(isCell)}
        : cells.toSet();
    for (final (previous, edge, exceptional) in predecessors[block]!) {
      final state = initialized[previous]!;
      final before = exceptional ? state.exceptional : state.normal;
      final incoming = before.toSet()..removeAll(block.parameters);
      for (final (i, parameter) in block.parameters.indexed) {
        if (isCell(parameter) && ready(edge.arguments[i], before)) {
          incoming.add(parameter);
        }
      }
      bound.retainAll(incoming);
    }
    Set<Value>? failed;
    for (final operation in operations(block)) {
      if (block.end case Invoke(operation: final invoked)
          when invoked == operation) {
        failed = bound.toSet();
      }
      switch (operation) {
        case NewCell(:final initial) when isCell(operation):
          bound.remove(operation);
          if (initial != null) bound.add(operation);
        case CopyCell(:final cell) when isCell(operation):
          final wasReady = ready(cell, bound);
          bound.remove(operation);
          if (wasReady) bound.add(operation);
        case WriteCell(:final cell) when isCell(cell):
          bound.add(cell);
          if (origins[cell]!.length == 1) bound.add(origins[cell]!.single);
        case ReadCell(:final cell)
            when isCell(cell) && check && !ready(cell, bound):
          throw UnsupportedError(
            'Native local may be read before initialization.',
          );
        default:
          break;
      }
    }
    return (normal: bound, exceptional: failed ?? bound);
  }

  do {
    changed = false;
    for (final block in function.blocks) {
      final next = after(block), previous = initialized[block]!;
      if (next.normal.length != previous.normal.length ||
          !next.normal.containsAll(previous.normal) ||
          next.exceptional.length != previous.exceptional.length ||
          !next.exceptional.containsAll(previous.exceptional)) {
        initialized[block] = next;
        changed = true;
      }
    }
  } while (changed);
  for (final block in function.blocks) {
    after(block, check: true);
  }
}
