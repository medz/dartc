import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';
import 'integer_range.dart';

/// Exposes individual executions of loops with a proven finite integer counter.
///
/// Each peel retains the original loop as its continuation. Fresh shared facts
/// then remove known computation before another execution is exposed. The code
/// growth budget bounds expansion, never the solver or the program's execution.
final class const ProgramLoopSpecialization({final int maxCodeGrowth = 64})
    extends ProgramPass {
  @override
  bool get expandsCode => true;

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  @override
  ProgramTransform bind() {
    RangeError.checkNotNegative(maxCodeGrowth, 'maxCodeGrowth');
    final remaining = <FunctionTarget, int>{};
    return (facts) {
      facts.checkProgram(facts.program);
      var changed = false;
      final functions = <IrFunction>[];
      for (final function in facts.program.functions) {
        var rewritten = function;
        final budget = remaining[function.target] ?? maxCodeGrowth;
        if (budget != 0 && facts.definitions.contains(function.target)) {
          final incoming = <Block, List<(Block, Jump)>>{
            for (final block in function.blocks) block: [],
          };
          for (final block in function.blocks) {
            for (final edge in block.successors) {
              incoming[edge.target]!.add((block, edge));
            }
          }
          final dominance = ValueDominance(function);
          ({Block header, Set<Block> region, int cost})? selected;
          for (final header in function.blocks) {
            if (header == function.entry || header.parameters.isEmpty) continue;
            final region = {
              for (final block in function.blocks)
                if (dominance.atEntry(header.parameters.first, block)) block,
            };
            final backs = [
              for (final (owner, edge) in incoming[header]!)
                if (region.contains(owner)) edge,
            ];
            if (backs.isEmpty) continue;
            final entries = [
              for (final (owner, edge) in incoming[header]!)
                if (!region.contains(owner) && facts.reachesEdge(edge)) edge,
            ];
            if (entries.isEmpty) continue;
            final loop = {header};
            final pending = [
              for (final (owner, _) in incoming[header]!)
                if (region.contains(owner)) owner,
            ];
            while (pending.isNotEmpty) {
              final block = pending.removeLast();
              if (!loop.add(block)) continue;
              pending.addAll(incoming[block]!.map((entry) => entry.$1));
            }
            if (!_finiteCounter(header, loop, entries, backs, facts)) continue;
            final cost = region.fold(
              0,
              (sum, block) =>
                  sum + block.instructions.length + block.parameters.length + 1,
            );
            if (cost > budget) continue;
            if (selected == null || cost < selected.cost) {
              selected = (header: header, region: region, cost: cost);
            }
          }
          if (selected != null) {
            rewritten = _peel(function, selected.header, selected.region);
            remaining[function.target] = budget - selected.cost;
            changed = true;
          }
        }
        functions.add(rewritten);
      }
      return changed
          ? IrProgram(
              facts.program.classes,
              functions,
              globals: facts.program.globals,
              externals: facts.program.externals,
            )
          : facts.program;
    };
  }
}

enum _Comparison() {
  lessThan,
  lessOrEqual,
  greaterThan,
  greaterOrEqual,
  equal,
  notEqual,
}

bool _finiteCounter(
  Block header,
  Set<Block> loop,
  List<Jump> entries,
  List<Jump> backs,
  ProgramFlowFacts facts,
) {
  final end = header.end;
  if (end is! Branch) return false;
  final taken = loop.contains(end.ifTrue.target);
  if (taken == loop.contains(end.ifFalse.target)) return false;
  final condition = end.condition;
  final (Value, Value, _Comparison)? relation = switch (condition) {
    IntBinary(operator: .lessThan, :final left, :final right) => (
      left,
      right,
      _Comparison.lessThan,
    ),
    IntBinary(operator: .lessOrEqual, :final left, :final right) => (
      left,
      right,
      _Comparison.lessOrEqual,
    ),
    IntBinary(operator: .greaterThan, :final left, :final right) => (
      left,
      right,
      _Comparison.greaterThan,
    ),
    IntBinary(operator: .greaterOrEqual, :final left, :final right) => (
      left,
      right,
      _Comparison.greaterOrEqual,
    ),
    Equals(:final left, :final right, :final negated) => (
      left,
      right,
      negated ? _Comparison.notEqual : _Comparison.equal,
    ),
    _ => null,
  };
  if (relation == null) return false;
  var (counter, limitValue, comparison) = relation;
  if (!header.parameters.contains(counter)) {
    if (!header.parameters.contains(limitValue)) return false;
    (counter, limitValue) = (limitValue, counter);
    comparison = switch (comparison) {
      .lessThan => .greaterThan,
      .lessOrEqual => .greaterOrEqual,
      .greaterThan => .lessThan,
      .greaterOrEqual => .lessOrEqual,
      .equal || .notEqual => comparison,
    };
  }
  if (!taken) {
    comparison = switch (comparison) {
      .lessThan => .greaterOrEqual,
      .lessOrEqual => .greaterThan,
      .greaterThan => .lessOrEqual,
      .greaterOrEqual => .lessThan,
      .equal => .notEqual,
      .notEqual => .equal,
    };
  }
  int? integer(Value value) => switch (facts.valueOf(value).constant) {
    ScalarConstant(value: final int value) => value,
    _ => null,
  };
  final limit = integer(limitValue),
      slot = header.parameters.indexOf(counter as BlockParameter);
  final starts = {for (final edge in entries) integer(edge.arguments[slot])};
  if (limit == null || starts.length != 1 || starts.single == null) {
    return false;
  }
  bool enters(int value) => switch (comparison) {
    .lessThan => value < limit,
    .lessOrEqual => value <= limit,
    .greaterThan => value > limit,
    .greaterOrEqual => value >= limit,
    .equal => value == limit,
    .notEqual => value != limit,
  };
  if (!enters(starts.single!)) return false;
  if (backs.every((edge) {
    final next = integer(edge.arguments[slot]);
    return next != null && !enters(next);
  })) {
    return true;
  }
  BigInt? amount(Value value) => switch (integer(value)) {
    final number? => BigInt.from(number),
    null => null,
  };
  final steps = <BigInt?>{};
  for (final edge in backs) {
    final update = edge.arguments[slot];
    steps.add(switch (update) {
      IntBinary(operator: .add, :final left, :final right)
          when left == counter =>
        amount(right),
      IntBinary(operator: .add, :final left, :final right)
          when right == counter =>
        amount(left),
      IntBinary(operator: .subtract, :final left, :final right)
          when left == counter =>
        amount(right) == null ? null : -amount(right)!,
      _ => null,
    });
  }
  if (steps.length != 1 ||
      steps.single == null ||
      steps.single == BigInt.zero) {
    return false;
  }
  final start = BigInt.from(starts.single!),
      stop = BigInt.from(limit),
      step = steps.single!;
  final distance = stop - start;
  final BigInt? count = switch (comparison) {
    .lessThan when step > BigInt.zero && distance > BigInt.zero =>
      (distance + step - BigInt.one) ~/ step,
    .lessOrEqual when step > BigInt.zero && distance >= BigInt.zero =>
      distance ~/ step + BigInt.one,
    .greaterThan when step < BigInt.zero && distance < BigInt.zero =>
      (-distance - step - BigInt.one) ~/ -step,
    .greaterOrEqual when step < BigInt.zero && distance <= BigInt.zero =>
      distance ~/ step + BigInt.one,
    .notEqual
        when distance != BigInt.zero &&
            distance % step == BigInt.zero &&
            distance ~/ step > BigInt.zero =>
      distance ~/ step,
    .equal when distance == BigInt.zero => BigInt.one,
    _ => null,
  };
  if (count == null) return false;
  final after = start + count * step;
  return after >= BigInt.from(FlowIntegerRange.minimum) &&
      after <= BigInt.from(FlowIntegerRange.maximum);
}

IrFunction _peel(IrFunction function, Block header, Set<Block> region) {
  final blocks = {
    for (final block in region)
      block: Block(block.parameters.map((value) => value.type)),
  };
  final values = <Value, Value>{
    for (final block in region)
      for (final (index, parameter) in block.parameters.indexed)
        parameter: blocks[block]!.parameters[index],
  };
  final owned = {
    for (final block in region) ...[
      ...block.instructions,
      if (block.end case Invoke(:final operation)) operation,
    ],
  };
  final origins = <Object, Object>{
    for (final entry in blocks.entries) entry.value: entry.key,
  };
  Value read(Value value) {
    if (values[value] case final copy?) return copy;
    if (value is Instruction && owned.contains(value)) {
      final copy = value.mapInputs(read);
      values[value] = copy;
      origins[copy] = value;
      return copy;
    }
    if (value is TestedValue && owned.contains(value.test)) {
      return (read(value.test) as TypeTest).refinement(value.outcome)!;
    }
    return value;
  }

  Jump edge(Jump source) => Jump(
    source.target == header ? header : blocks[source.target] ?? source.target,
    source.arguments.map(read),
  );
  for (final block in region) {
    final copy = blocks[block]!;
    for (final operation in block.instructions) {
      copy.emit(read(operation) as Instruction);
    }
    copy.finish(_mapEnd(block.end, read, edge));
  }
  final ends = <Block, Terminator>{};
  for (final block in function.blocks) {
    if (region.contains(block) ||
        !block.successors.any((edge) => edge.target == header)) {
      continue;
    }
    ends[block] = _mapEnd(
      block.end,
      (value) => value,
      (edge) => Jump(
        edge.target == header ? blocks[header]! : edge.target,
        edge.arguments,
      ),
    );
  }
  return FunctionRewrite(function, terminators: ends, origins: origins).run();
}

Terminator _mapEnd(
  Terminator end,
  Value Function(Value) read,
  Jump Function(Jump) edge,
) => switch (end) {
  Return(:final value) => Return(value == null ? null : read(value)),
  final Jump jump => edge(jump),
  Branch(:final condition, :final ifTrue, :final ifFalse) => Branch(
    read(condition),
    edge(ifTrue),
    edge(ifFalse),
  ),
  Invoke(:final operation, :final onReturn, :final onThrow) => Invoke(
    read(operation) as Instruction,
    onReturn: onReturn == null ? null : edge(onReturn),
    onThrow: edge(onThrow),
  ),
  Throw(
    :final exception,
    :final stackTrace,
    :final onThrow,
    :final isRecorded,
  ) =>
    isRecorded
        ? Throw.recorded(
            read(exception),
            read(stackTrace!),
            onThrow: onThrow == null ? null : edge(onThrow),
          )
        : Throw(
            read(exception),
            stackTrace: stackTrace == null ? null : read(stackTrace),
            onThrow: onThrow == null ? null : edge(onThrow),
          ),
  ExhaustivenessFailure(:final onThrow) => ExhaustivenessFailure(
    onThrow == null ? null : edge(onThrow),
  ),
  Unreachable(:final cause) => Unreachable(read(cause)),
  Await() || Yield() || YieldStream() => throw StateError(
    'Normalize suspension before specializing a loop.',
  ),
};
