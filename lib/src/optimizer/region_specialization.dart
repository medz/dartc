import 'package:dartc/ir.dart';

import 'function_rewrite.dart';

/// Copies a dominated region for selected incoming edges, retaining back edges.
IrFunction specializeRegion(
  IrFunction function,
  Block header,
  Set<Block> region,
  Set<Jump> entries,
) {
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
    if (!block.successors.any(entries.contains)) {
      continue;
    }
    ends[block] = _mapEnd(
      block.end,
      (value) => value,
      (edge) => Jump(
        entries.contains(edge) ? blocks[header]! : edge.target,
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
    'Normalize suspension before specializing control flow.',
  ),
};
