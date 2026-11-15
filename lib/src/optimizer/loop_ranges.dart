import 'package:dartc/ir.dart';

import 'integer_range.dart';

/// Natural loops and affine transfers between their integer parameters.
final class LoopRanges(final IrFunction function) {
  final incoming = <Block, List<(Block, Jump)>>{};
  final owners = <Value, Block>{};
  late final dominance = ValueDominance(function);
  late final loops = <LoopRange>[];

  this {
    for (final block in function.blocks) {
      incoming.putIfAbsent(block, () => []);
      for (final value in [
        ...block.parameters,
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ]) {
        owners[value] = block;
      }
      for (final edge in block.successors) {
        incoming.putIfAbsent(edge.target, () => []).add((block, edge));
      }
    }
    for (final header in function.blocks) {
      if (header == function.entry || header.parameters.isEmpty) continue;
      final backs = [
        for (final (owner, edge) in incoming[header]!)
          if (dominance.atEntry(header.parameters.first, owner)) edge,
      ];
      if (backs.isEmpty) continue;
      final blocks = {header};
      final pending = [
        for (final (owner, edge) in incoming[header]!)
          if (backs.contains(edge)) owner,
      ];
      while (pending.isNotEmpty) {
        final block = pending.removeLast();
        if (!blocks.add(block)) continue;
        pending.addAll(incoming[block]!.map((entry) => entry.$1));
      }
      if (blocks.any(
        (block) => !dominance.atEntry(header.parameters.first, block),
      )) {
        continue;
      }
      loops.add(LoopRange(this, header, blocks, backs));
    }
  }
}

final class LoopRange(
  final LoopRanges graph,
  final Block header,
  final Set<Block> blocks,
  final List<Jump> backs,
) {
  Iterable<Jump> get entries => [
    for (final (owner, edge) in graph.incoming[header]!)
      if (!blocks.contains(owner)) edge,
  ];

  bool guards(Block block) {
    if (block.end case Branch(
      :final condition,
      :final ifTrue,
      :final ifFalse,
    )) {
      final operands = switch (condition) {
        IntBinary() || Equals() => (condition as Instruction).inputs,
        _ => const <Value>[],
      };
      return operands.any(header.parameters.contains) &&
          blocks.contains(ifTrue.target) != blocks.contains(ifFalse.target);
    }
    return false;
  }

  /// Bounds require a loop-invariant guard and nonwrapping monotone progress.
  /// Paths may increment other parameters by different amounts on each turn.
  LoopRangeProof? prove(
    FlowIntegerRange? Function(Value) read,
    bool Function(Instruction) isPure,
  ) {
    final invariant = <Value, bool>{};
    bool fixed(Value value) {
      if (value is Constant || !blocks.contains(graph.owners[value])) {
        return true;
      }
      if (invariant[value] case final known?) return known;
      invariant[value] = false;
      return invariant[value] = switch (value) {
        BlockParameter() when graph.owners[value] != header =>
          graph.incoming[graph.owners[value]]!.every(
            (entry) => fixed(
              entry.$2.arguments[graph.owners[value]!.parameters.indexOf(
                value,
              )],
            ),
          ),
        final Instruction operation =>
          isPure(operation) && operation.inputs.every(fixed),
        _ => false,
      };
    }

    final offsets = <BlockParameter, Map<Value, FlowIntegerRange?>>{};
    FlowIntegerRange? offset(Value value, BlockParameter base) {
      if (value == base) return FlowIntegerRange(0, 0);
      final known = offsets.putIfAbsent(base, () => {});
      if (known.containsKey(value)) return known[value];
      known[value] = null;
      FlowIntegerRange? result;
      switch (value) {
        case IntBinary(:final operator, :final left, :final right):
          final a = offset(left, base);
          final b = fixed(right) ? read(right) : null;
          if (a != null && b != null) {
            result = switch (operator) {
              .add => a.add(b),
              .subtract => a.subtract(b),
              _ => null,
            };
          } else if (operator == .add && fixed(left)) {
            final a = read(left), b = offset(right, base);
            if (a != null && b != null) result = a.add(b);
          }
        case BlockParameter() when graph.owners[value] != header:
          final owner = graph.owners[value]!;
          final index = owner.parameters.indexOf(value);
          for (final (_, edge) in graph.incoming[owner]!) {
            final next = offset(edge.arguments[index], base);
            if (next == null) return null;
            result = result == null ? next : result.join(next);
          }
        default:
          break;
      }
      return known[value] = result == FlowIntegerRange.full ? null : result;
    }

    final starts = <BlockParameter, FlowIntegerRange>{};
    final steps = <BlockParameter, FlowIntegerRange>{};
    for (final (index, parameter) in header.parameters.indexed) {
      if (parameter.type != ValueType.integer) continue;
      FlowIntegerRange? start, step;
      for (final edge in entries) {
        final value = read(edge.arguments[index]);
        if (value == null) {
          start = null;
          break;
        }
        start = start == null ? value : start.join(value);
      }
      for (final edge in backs) {
        final value = offset(edge.arguments[index], parameter);
        if (value == null) {
          step = null;
          break;
        }
        step = step == null ? value : step.join(value);
      }
      if (start != null) starts[parameter] = start;
      if (start != null && step != null) steps[parameter] = step;
    }
    for (final guard in blocks.where(guards)) {
      final end = guard.end;
      if (end is! Branch) continue;
      final comparison = switch (end.condition) {
        IntBinary(:final operator, :final left, :final right) =>
          switch (operator) {
            .lessThan => (left, right, _Comparison.lessThan),
            .lessOrEqual => (left, right, _Comparison.lessOrEqual),
            .greaterThan => (left, right, _Comparison.greaterThan),
            .greaterOrEqual => (left, right, _Comparison.greaterOrEqual),
            _ => null,
          },
        Equals(:final left, :final right, :final negated) => (
          left,
          right,
          negated ? _Comparison.notEqual : _Comparison.equal,
        ),
        _ => null,
      };
      if (comparison == null) continue;
      var (counter, limitValue, operator) = comparison;
      if (!starts.containsKey(counter)) {
        (counter, limitValue) = (limitValue, counter);
        operator = _reverse(operator);
      }
      if (counter is! BlockParameter || !starts.containsKey(counter)) continue;
      final taken = blocks.contains(end.ifTrue.target);
      if (taken == blocks.contains(end.ifFalse.target)) continue;
      if (!taken) operator = _negate(operator);
      if (!fixed(limitValue)) continue;
      final limit = read(limitValue)?.constant;
      if (limit == null) continue;
      final continuation = taken ? end.ifTrue : end.ifFalse;
      final beforeGuard = <Block>{};
      final pending = [header];
      while (pending.isNotEmpty) {
        final block = pending.removeLast();
        if (!blocks.contains(block) || !beforeGuard.add(block)) continue;
        for (final edge in block.successors) {
          if (edge != continuation && !backs.contains(edge)) {
            pending.add(edge.target);
          }
        }
      }
      if (graph.incoming[header]!.any(
        (entry) =>
            entry.$2 != continuation &&
            backs.contains(entry.$2) &&
            beforeGuard.contains(entry.$1),
      )) {
        continue;
      }
      bool enters(int value) => switch (operator) {
        .lessThan => value < limit,
        .lessOrEqual => value <= limit,
        .greaterThan => value > limit,
        .greaterOrEqual => value >= limit,
        .equal => value == limit,
        .notEqual => value != limit,
      };
      final slot = header.parameters.indexOf(counter);
      if (backs.every((edge) {
        final next = edge.arguments[slot];
        final value = read(next)?.constant;
        return fixed(next) && value != null && !enters(value);
      })) {
        return LoopRangeProof(this, {}, {}, {}, {});
      }
      final start = starts[counter]!, step = steps[counter];
      if (step == null) continue;
      BigInt? count;
      final stop = BigInt.from(limit);
      if (step.lower > 0 &&
          (operator == .lessThan || operator == .lessOrEqual)) {
        final last = stop - (operator == .lessThan ? BigInt.one : BigInt.zero);
        if (last + BigInt.from(step.upper) > _maximum) continue;
        final distance = last - BigInt.from(start.lower);
        count = distance < BigInt.zero
            ? BigInt.zero
            : distance ~/ BigInt.from(step.lower) + BigInt.one;
      } else if (step.upper < 0 &&
          (operator == .greaterThan || operator == .greaterOrEqual)) {
        final last =
            stop + (operator == .greaterThan ? BigInt.one : BigInt.zero);
        if (last + BigInt.from(step.lower) < _minimum) continue;
        final distance = BigInt.from(start.upper) - last;
        count = distance < BigInt.zero
            ? BigInt.zero
            : distance ~/ -BigInt.from(step.upper) + BigInt.one;
      } else if (start.constant case final first?
          when step.constant != null && step.constant != 0) {
        final distance = stop - BigInt.from(first),
            amount = BigInt.from(step.constant!);
        if (operator == .notEqual &&
            distance % amount == BigInt.zero &&
            distance ~/ amount > BigInt.zero) {
          count = distance ~/ amount;
        } else if (operator == .equal && distance == BigInt.zero) {
          count = BigInt.one;
        }
      }
      if (count == null || count == BigInt.zero) continue;
      if (_range(
            BigInt.from(start.lower) + BigInt.from(step.lower) * count,
            BigInt.from(start.upper) + BigInt.from(step.upper) * count,
          ) ==
          null) {
        continue;
      }
      final all = <BlockParameter, FlowIntegerRange>{};
      final body = <BlockParameter, FlowIntegerRange>{};
      for (final parameter in steps.keys) {
        final start = starts[parameter]!, step = steps[parameter]!;
        FlowIntegerRange? after(BigInt iterations) => _range(
          BigInt.from(start.lower) +
              (step.lower < 0
                  ? BigInt.from(step.lower) * iterations
                  : BigInt.zero),
          BigInt.from(start.upper) +
              (step.upper > 0
                  ? BigInt.from(step.upper) * iterations
                  : BigInt.zero),
        );
        final maximum = after(count), entering = after(count - BigInt.one);
        if (maximum != null && entering != null) {
          all[parameter] = maximum;
          body[parameter] = entering;
          for (final value in graph.owners.keys) {
            if (blocks.contains(graph.owners[value])) offset(value, parameter);
          }
        }
      }
      return LoopRangeProof(
        this,
        all,
        body,
        blocks.difference(beforeGuard),
        offsets,
      );
    }
    return null;
  }
}

final class LoopRangeProof(
  final LoopRange loop,
  final Map<BlockParameter, FlowIntegerRange> all,
  final Map<BlockParameter, FlowIntegerRange> body,
  final Set<Block> iteration,
  final Map<BlockParameter, Map<Value, FlowIntegerRange?>> offsets,
) {
  FlowIntegerRange? range(Value value, Block block) {
    for (final parameter in all.keys) {
      final delta = value == parameter
          ? FlowIntegerRange(0, 0)
          : offsets[parameter]?[value];
      if (delta == null) continue;
      final bounds =
          iteration.contains(block) ||
              iteration.contains(loop.graph.owners[value])
          ? body[parameter]!
          : all[parameter]!;
      return _range(
        BigInt.from(bounds.lower) + BigInt.from(delta.lower),
        BigInt.from(bounds.upper) + BigInt.from(delta.upper),
      );
    }
    return null;
  }
}

final _minimum = BigInt.from(FlowIntegerRange.minimum);
final _maximum = BigInt.from(FlowIntegerRange.maximum);

FlowIntegerRange? _range(BigInt low, BigInt high) =>
    low < _minimum || high > _maximum
    ? null
    : FlowIntegerRange(low.toInt(), high.toInt());

enum _Comparison() {
  lessThan,
  lessOrEqual,
  greaterThan,
  greaterOrEqual,
  equal,
  notEqual,
}

_Comparison _reverse(_Comparison operator) => switch (operator) {
  .lessThan => .greaterThan,
  .lessOrEqual => .greaterOrEqual,
  .greaterThan => .lessThan,
  .greaterOrEqual => .lessOrEqual,
  _ => operator,
};

_Comparison _negate(_Comparison operator) => switch (operator) {
  .lessThan => .greaterOrEqual,
  .lessOrEqual => .greaterThan,
  .greaterThan => .lessOrEqual,
  .greaterOrEqual => .lessThan,
  .equal => .notEqual,
  .notEqual => .equal,
};
