import 'package:dartc/ir.dart';

import 'selected_function.dart';

/// Tracks live values across semantic or selected control-flow edges and calls.
final class FunctionLiveness._(
  List<Block> blocks,
  Block entry,
  List<BlockParameter> Function(Block) parametersOf,
  List<Value> Function(Block) instructionsOf,
  Terminator Function(Block) endOf,
  List<Value> Function(Jump) argumentsOf,
  Iterable<Value> Function(Value) inputsOf,
  Set<Value> calls, {
  Set<NewCell> stackCells = const {},
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

  new(
    SelectedFunction body,
    Iterable<Value> Function(Value) inputsOf,
    Set<Value> calls, {
    Iterable<Value> Function(Terminator)? extraInputs,
  }) : this._(
         body.blocks,
         body.entry,
         body.parametersOf,
         (block) => body.instructions[block]!,
         (block) => body.ends[block]!,
         body.argumentsOf,
         inputsOf,
         calls,
         stackCells: body.stackCells,
         introduced: body.introduced,
         extraInputs: extraInputs,
       );

  /// Semantic liveness before representation or machine operands are selected.
  new source(IrFunction body)
    : this._(
        body.blocks,
        body.entry,
        (block) => block.parameters,
        (block) => [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
        (block) => block.end,
        (edge) => edge.arguments,
        (value) => (value as Instruction).inputs,
        const {},
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
        if (value is! Constant && value is! UnwindValue) yield value;
      }
    }

    Set<Value> transfer(Block block, {bool record = false}) {
      final end = endOf(block);
      final live = <Value>{};
      final counts = record ? uses[block] = <Value, int>{} : null;
      void read(Value value) {
        if (value is TestedValue) value = value.test.operand;
        if (counts != null && !stackCells.contains(value)) {
          counts.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
        if (value is! Constant && value is! UnwindValue) live.add(value);
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
        live.remove(
          instruction is WriteCell && stackCells.contains(instruction.cell)
              ? instruction.cell
              : instruction,
        );
        if (end case Invoke(operation: WriteCell(:final cell), :final onThrow)
            when end.operation == instruction &&
                edgeValues(onThrow).contains(cell)) {
          live.add(cell);
        }
        if (record && calls.contains(instruction)) {
          acrossCalls[instruction] = {...live};
        }
        for (final input in inputsOf(instruction)) {
          // Writing needs the slot's address, not its previous contents.
          if (instruction is! WriteCell ||
              !stackCells.contains(instruction.cell) ||
              input != instruction.cell) {
            read(input);
          }
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
