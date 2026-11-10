import 'package:dartc/ir.dart';

/// Tracks selected reads through branches, block arguments and local writes.
final class FunctionLiveness(
  IrFunction function,
  Iterable<Value> Function(Instruction) inputsOf,
) {
  /// Values needed at entry, including used parameters and local contents.
  final liveIn = <Block, Set<Value>>{};

  /// Values needed by at least one successor, before argument assignment.
  final liveOut = <Block, Set<Value>>{};

  /// Parameter positions whose incoming values must be copied.
  final liveParameters = <Block, List<int>>{};

  /// Physical operand reads in each block, excluding local storage addresses.
  final uses = <Block, Map<Value, int>>{};

  /// Values needed after a call, excluding the result it has yet to produce.
  final acrossCalls = <Instruction, Set<Value>>{};

  this {
    final reads = <Block, Set<Value>>{}, writes = <Block, Set<Value>>{};
    final positions = {
      for (final block in function.blocks)
        for (final (i, parameter) in block.parameters.indexed)
          parameter: (block, i),
    };
    for (final block in function.blocks) {
      final used = reads[block] = {}, defined = writes[block] = {};
      liveIn[block] = {};
      liveOut[block] = {};
      final counts = uses[block] = {};
      void read(Value value) {
        if (value is! NewCell) {
          counts.update(value, (n) => n + 1, ifAbsent: () => 1);
        }
        if (value is! Constant && !defined.contains(value)) used.add(value);
      }

      for (final instruction in block.instructions) {
        for (final input in inputsOf(instruction)) {
          // A write needs the slot's address, not its previous contents.
          if (instruction is! WriteCell || input != instruction.cell) {
            read(input);
          }
        }
        defined.add(instruction is WriteCell ? instruction.cell : instruction);
      }
      switch (block.end) {
        case Return(value: final value?) when value.type != .voidType:
          read(value);
        case Branch(:final condition):
          read(condition);
        case Jump() || Return():
          break;
        default:
          throw UnsupportedError('Native terminator: ${block.end.runtimeType}');
      }
    }

    bool changed;
    do {
      changed = false;
      for (final block in function.blocks.reversed) {
        final next = <Value>{};
        for (final edge in block.successors) {
          for (var value in liveIn[edge.target]!) {
            if (positions[value] case (final owner, final index)
                when owner == edge.target) {
              value = edge.arguments[index];
            }
            if (value is TestedValue) value = value.test.operand;
            if (value is! Constant) next.add(value);
          }
        }
        liveOut[block] = next;
        final incoming = liveIn[block]!;
        final length = incoming.length;
        incoming
          ..addAll(reads[block]!)
          ..addAll(next.where((v) => !writes[block]!.contains(v)));
        changed |= incoming.length != length;
      }
    } while (changed);

    for (final block in function.blocks) {
      liveParameters[block] = [
        for (final (i, parameter) in block.parameters.indexed)
          if (liveIn[block]!.contains(parameter)) i,
      ];
    }
    for (final block in function.blocks) {
      for (final edge in block.successors) {
        for (final i in liveParameters[edge.target]!) {
          final argument = edge.arguments[i];
          final stored = argument is TestedValue
              ? argument.test.operand
              : argument;
          if (stored is! NewCell) {
            uses[block]!.update(stored, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
    }
    for (final block in function.blocks) {
      final live = {...liveOut[block]!};
      switch (block.end) {
        case Return(value: final value?) when value.type != .voidType:
          if (value is! Constant) live.add(value);
        case Branch(:final condition):
          if (condition is! Constant) live.add(condition);
        default:
          break;
      }
      for (final instruction in block.instructions.reversed) {
        live.remove(instruction is WriteCell ? instruction.cell : instruction);
        if (instruction is DirectCall || instruction is NativeCall) {
          acrossCalls[instruction] = {...live};
        }
        for (final input in inputsOf(instruction)) {
          if (input is! Constant &&
              (instruction is! WriteCell || input != instruction.cell)) {
            live.add(input);
          }
        }
      }
    }
  }
}
