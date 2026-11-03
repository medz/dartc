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

  /// Writable bindings and their declared types, in edge-argument order.
  final mutableLocals = <(VariableElement, ValueType)>[];

  /// The block receiving instructions, or `null` after a terminating transfer.
  Block? current;

  /// Appends an open block with parameters of [types] and returns it.
  Block addBlock([Iterable<ValueType> types = const []]) {
    final block = Block(types);
    blocks.add(block);
    return block;
  }

  /// Captures the bindings that may differ when another path reaches this point.
  List<Value> saveLocals([int? count]) {
    final end = count ?? mutableLocals.length;
    return end == 0
        ? const []
        : [for (var i = 0; i < end; i++) locals[mutableLocals[i].$1]!];
  }

  /// Restores [values] at the same lexical scope in which they were captured.
  void restoreLocals(List<Value> values) {
    for (final (i, (variable, _)) in mutableLocals.indexed) {
      locals[variable] = values[i];
    }
  }

  /// Returns edges from the [saved] and active paths to a new current block.
  ///
  /// If both paths produce a [result], the first block parameter carries it.
  /// The remaining parameters carry only locals that differ across the paths.
  (Jump, Jump) join(List<Value> saved, [(ValueType, Value, Value)? result]) {
    final types = <ValueType>[if (result != null) result.$1];
    final first = <Value>[if (result != null) result.$2];
    final second = <Value>[if (result != null) result.$3];
    final changed = <VariableElement>[];
    for (final (i, (variable, type)) in mutableLocals.indexed) {
      final value = locals[variable]!;
      if (saved[i] == value) continue;
      types.add(type);
      first.add(saved[i]);
      second.add(value);
      changed.add(variable);
    }
    final block = addBlock(types);
    var slot = result == null ? 0 : 1;
    for (final variable in changed) {
      locals[variable] = block.parameters[slot++];
    }
    current = block;
    return (.new(block, first), .new(block, second));
  }

  /// Lowers alternatives from the same local state and joins paths that return normally.
  Value? branch(
    Value condition,
    Value? Function() ifTrue,
    Value? Function() ifFalse, [
    ValueType? resultType,
  ]) {
    if (condition case Constant(value: final bool taken)) {
      return taken ? ifTrue() : ifFalse();
    }
    final yes = addBlock(), no = addBlock();
    current!.finish(Branch(condition, .new(yes), .new(no)));
    final before = saveLocals();
    current = yes;
    final left = ifTrue(), yesEnd = current;
    final yesValues = yesEnd == null ? null : saveLocals();
    current = no;
    restoreLocals(before);
    final right = ifFalse(), noEnd = current;
    if (yesEnd == null) return right;
    if (noEnd == null) {
      current = yesEnd;
      restoreLocals(yesValues!);
      return left;
    }
    final (fromYes, fromNo) = join(
      yesValues!,
      resultType == null ? null : (resultType, left!, right!),
    );
    yesEnd.finish(fromYes);
    noEnd.finish(fromNo);
    return resultType == null ? null : current!.parameters.first;
  }
}

/// A jump destination carrying only the mutable locals visible at its boundary.
final class JumpTarget(final FunctionContext _context) {
  final _localCount = _context.mutableLocals.length;
  Block? _block;

  /// Creates the destination on its first incoming edge.
  Jump edge() {
    final values = _context.saveLocals(_localCount);
    return .new(
      _block ??= _context.addBlock(
        _context.mutableLocals.take(_localCount).map((v) => v.$2),
      ),
      values,
    );
  }

  /// Transfers the open path, if any, to this target.
  void jump() {
    _context.current?.finish(edge());
    _context.current = null;
  }

  /// Merges incoming jumps with fallthrough in the target's lexical scope.
  void enter() {
    final block = _block;
    if (block == null) return;
    _context.current?.finish(edge());
    _context.current = block;
    _context.restoreLocals(block.parameters);
  }
}
