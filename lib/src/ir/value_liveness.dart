import 'block.dart';
import 'function.dart';
import 'value.dart';

/// Tracks live values across semantic or selected control-flow edges and calls.
base class ValueLiveness(
  List<Block> blocks,
  Block entry,
  List<BlockParameter> Function(Block) parametersOf,
  List<Value> Function(Block) instructionsOf,
  Terminator Function(Block) endOf,
  List<Value> Function(Jump) argumentsOf,
  Iterable<Value> Function(Value) inputsOf,
  Set<Value> calls, {
  Set<Instruction> introduced = const {},
  Iterable<Value> Function(Terminator)? extraInputs,
}) {
  final liveIn = <Block, Set<Value>>{};
  final liveOut = <Block, Set<Value>>{};
  final liveParameters = <Block, List<int>>{};
  final uses = <Block, Map<Value, int>>{};
  final acrossCalls = <Value, Set<Value>>{};

  /// Introduced conversions whose results are never consumed.
  final omitted = <Value>{};

  /// Semantic liveness before representation or machine operands are selected.
  new source(IrFunction body, {Set<Value> calls = const {}})
    : this(
        body.blocks,
        body.entry,
        (block) => block.parameters,
        (block) => [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
        (block) => block.end,
        (edge) => edge.arguments,
        (value) => [
          ...(value as Instruction).inputs,
          ...body.typeInputsOf(value),
        ],
        calls,
      );

  this {
    final positions = {
      for (final block in blocks)
        for (final (i, parameter) in parametersOf(block).indexed)
          parameter: (block, i),
    };
    for (final block in blocks) {
      liveIn[block] = {};
    }

    Iterable<Value> edgeValues(Jump edge) sync* {
      for (var value in liveIn[edge.target]!) {
        if (positions[value] case (final owner, final index)
            when owner == edge.target) {
          value = argumentsOf(edge)[index];
        }
        if (value is TestedValue) value = value.test.operand;
        if (value is! Constant &&
            value is! UnwindValue &&
            value is! CallFrameValue) {
          yield value;
        }
      }
    }

    Set<Value> transfer(Block block, {bool record = false}) {
      final end = endOf(block);
      final live = <Value>{};
      final counts = record ? uses[block] = <Value, int>{} : null;
      void read(Value value) {
        if (value is TestedValue) value = value.test.operand;
        if (counts != null) {
          counts.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
        if (value is! Constant &&
            value is! UnwindValue &&
            value is! CallFrameValue) {
          live.add(value);
        }
      }

      for (final edge in endOf(block).successors) {
        live.addAll(edgeValues(edge));
      }
      if (end is Await) live.remove(end.result);
      liveOut[block] = {...live};
      if (record) {
        for (final edge in endOf(block).successors) {
          for (final index in liveParameters[edge.target]!) {
            read(argumentsOf(edge)[index]);
          }
        }
      }
      switch (end) {
        case YieldStream(:final stream):
          read(stream);
        case Yield(:final value):
          read(value);
        case Await(:final operand):
          read(operand);
        case Return(value: final value?):
          read(value);
        case Branch(:final condition):
          read(condition);
        case Throw(:final exception, :final stackTrace):
          read(exception);
          if (stackTrace != null) read(stackTrace);
        case Unreachable(:final cause):
          if (cause.type != .never) read(cause);
        case Jump() || Return() || Invoke() || ExhaustivenessFailure():
          break;
      }
      for (final value in extraInputs?.call(end) ?? const <Value>[]) {
        read(value);
      }
      for (final instruction in instructionsOf(block).reversed) {
        if (introduced.contains(instruction) && !live.contains(instruction)) {
          if (record) omitted.add(instruction);
          continue;
        }
        live.remove(instruction);
        if (record && calls.contains(instruction)) {
          acrossCalls[instruction] = {...live};
        }
        for (final input in inputsOf(instruction)) {
          read(input);
        }
      }
      return live;
    }

    bool changed;
    do {
      changed = false;
      for (final block in blocks.reversed) {
        final incoming = liveIn[block]!, length = incoming.length;
        incoming.addAll(transfer(block));
        changed |= incoming.length != length;
      }
    } while (changed);
    final parameters = parametersOf(entry).toSet();
    if (liveIn[entry]!.any((value) => !parameters.contains(value))) {
      throw StateError('Selected value lacks a dominating definition.');
    }
    for (final block in blocks) {
      liveParameters[block] = [
        for (final (i, parameter) in parametersOf(block).indexed)
          if (liveIn[block]!.contains(parameter)) i,
      ];
    }
    for (final block in blocks) {
      transfer(block, record: true);
    }
  }
}
