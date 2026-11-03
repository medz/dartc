import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:dartc/ir.dart';

import 'bindings.dart';

/// The open control-flow graph and local bindings for one function.
final class FunctionContext(
  /// The source unit used for resolved identities and diagnostic locations.
  final ResolvedUnitResult unit,

  /// The call targets shared by all functions in this batch.
  final TargetBindings bindings,
) {
  /// The blocks created so far, with the function entry first.
  final blocks = <Block>[];

  /// The SSA value of each in-scope variable on the current path.
  final locals = <VariableElement, Value>{};

  /// In-scope locals with writes, in the order used by snapshots and loop edges.
  final mutableLocals = <VariableElement>[];

  /// The block receiving instructions, or `null` after a terminating transfer.
  Block? current;

  /// Appends an open block with parameters of [types] and returns it.
  Block addBlock([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    blocks.add(block);
    return block;
  }

  /// Captures the bindings that may differ when another path reaches this point.
  List<Value> saveLocals() => mutableLocals.isEmpty
      ? const []
      : [for (final variable in mutableLocals) locals[variable]!];

  /// Restores [values] at the same lexical scope in which they were captured.
  void restoreLocals(List<Value> values) {
    for (final (i, variable) in mutableLocals.indexed) {
      locals[variable] = values[i];
    }
  }

  /// Returns edges from the [saved] and active paths to a new current block.
  ///
  /// If both paths produce a [result], the first block parameter carries it.
  /// The remaining parameters carry only locals that differ across the paths.
  (Jump, Jump) join(List<Value> saved, [(Value, Value)? result]) {
    final first = <Value>[if (result != null) result.$1];
    final second = <Value>[if (result != null) result.$2];
    final changed = <VariableElement>[];
    for (final (i, variable) in mutableLocals.indexed) {
      final value = locals[variable]!;
      if (saved[i] == value) continue;
      first.add(saved[i]);
      second.add(value);
      changed.add(variable);
    }
    final block = addBlock(first.map((v) => v.type));
    var slot = result == null ? 0 : 1;
    for (final variable in changed) {
      locals[variable] = block.parameters[slot++];
    }
    current = block;
    return (.new(block, first), .new(block, second));
  }
}
