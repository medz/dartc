import 'package:dartc/ir.dart';

import 'selected_function.dart';

/// Tracks selected values and local contents across control-flow edges and calls.
final class FunctionLiveness(
  SelectedFunction body,
  Iterable<Value> Function(Value) inputsOf,
  Set<Value> calls, {
  Iterable<Value> Function(Terminator)? extraInputs,
}) {
  final liveIn = <Block, Set<Value>>{};
  final liveOut = <Block, Set<Value>>{};
  final liveParameters = <Block, List<int>>{};
  final uses = <Block, Map<Value, int>>{};
  final acrossCalls = <Value, Set<Value>>{};

  /// Introduced conversions whose results are never consumed.
  final omitted = <Value>{};

  this {
    final positions = {
      for (final block in body.blocks)
        for (final (i, parameter) in body.parametersOf(block).indexed)
          parameter: (block, i),
    };
    for (final block in body.blocks) {
      liveIn[block] = {};
    }

    Iterable<Value> edgeValues(Jump edge) sync* {
      for (var value in liveIn[edge.target]!) {
        if (positions[value] case (final owner, final index)
            when owner == edge.target) {
          value = body.argumentsOf(edge)[index];
        }
        if (value is TestedValue) value = value.test.operand;
        if (value is! Constant && value is! UnwindValue) yield value;
      }
    }

    Set<Value> transfer(Block block, {bool record = false}) {
      final end = body.ends[block]!;
      final live = <Value>{};
      final counts = record ? uses[block] = <Value, int>{} : null;
      void read(Value value) {
        if (value is TestedValue) value = value.test.operand;
        if (counts != null && !body.stackCells.contains(value)) {
          counts.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
        if (value is! Constant && value is! UnwindValue) live.add(value);
      }

      for (final edge in body.successors(block)) {
        live.addAll(edgeValues(edge));
      }
      if (end is Await) live.remove(end.result);
      liveOut[block] = {...live};
      if (record) {
        for (final edge in body.successors(block)) {
          for (final index in liveParameters[edge.target]!) {
            read(body.argumentsOf(edge)[index]);
          }
        }
      }
      switch (end) {
        case Await(:final operand):
          read(body.operandsForAwait[end] ?? operand);
        case Return(value: final value?):
          read(value);
        case Branch(:final condition):
          read(condition);
        case Throw(:final exception, :final stackTrace):
          read(exception);
          if (stackTrace != null) read(stackTrace);
        case Jump() ||
            Return() ||
            Invoke() ||
            Unreachable() ||
            ExhaustivenessFailure():
          break;
        default:
          throw UnsupportedError('Native terminator: ${end.runtimeType}');
      }
      for (final value in extraInputs?.call(end) ?? const <Value>[]) {
        read(value);
      }
      for (final instruction in body.instructions[block]!.reversed) {
        if (body.introduced.contains(instruction) &&
            !live.contains(instruction)) {
          if (record) omitted.add(instruction);
          continue;
        }
        live.remove(
          instruction is WriteCell && body.stackCells.contains(instruction.cell)
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
              !body.stackCells.contains(instruction.cell) ||
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
      for (final block in body.blocks.reversed) {
        final incoming = liveIn[block]!, length = incoming.length;
        incoming.addAll(transfer(block));
        changed |= incoming.length != length;
      }
    } while (changed);
    final parameters = body.parametersOf(body.entry).toSet();
    if (liveIn[body.entry]!.any((value) => !parameters.contains(value))) {
      throw StateError('Selected value lacks a dominating definition.');
    }
    for (final block in body.blocks) {
      liveParameters[block] = [
        for (final (i, parameter) in body.parametersOf(block).indexed)
          if (liveIn[block]!.contains(parameter)) i,
      ];
    }
    for (final block in body.blocks) {
      transfer(block, record: true);
    }
  }
}
