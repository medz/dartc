import 'instruction.dart';
import 'module.dart';
import 'verify.dart';

/// Executes a program by the rules of Dart.
final class HirInterpreter(final HirModule module) {
  this {
    verifyHir(module);
  }

  /// The argument of the `exit` ending the program, or null if it returned.
  int? run() {
    final values = <HirInstruction, int>{};
    final body = module.main.body;
    for (final instruction in body.instructions) {
      values[instruction] = switch (instruction) {
        HirInt(:final value) => value,
        HirIntBinary(:final operator, :final left, :final right) => _binary(
          operator,
          values[left]!,
          values[right]!,
        ),
        HirIntUnary(:final operator, :final operand) => switch (operator) {
          .negate => -values[operand]!,
          .complement => ~values[operand]!,
        },
      };
    }
    return switch (body.terminator!) {
      HirReturn() => null,
      HirExit(:final code) => values[code],
    };
  }

  int _binary(HirIntOperator operator, int left, int right) =>
      switch (operator) {
        .add => left + right,
        .subtract => left - right,
        .multiply => left * right,
        .and => left & right,
        .or => left | right,
        .xor => left ^ right,
      };
}
