import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

/// The function that starts the program and returns its exit code.
const entrySymbol = '.start';

final _exit = LirSignature([.i64]);

/// Lowers a program to a closed machine-level module.
LirModule lowerProgram(HirModule module) {
  verifyHir(module);
  final main = _FunctionLowering().lower(module.main);
  final start = LirBlock()..add(Call(main.name, main.signature, const []));
  start.end(Return(start.add(ConstInt(0))));
  return LirModule(
    functions: [
      main,
      LirFunction(entrySymbol, LirSignature([], .i64), [start]),
    ],
    externals: [LirExternal('exit', _exit)],
  );
}

final class _FunctionLowering() {
  final _values = <HirInstruction, LirValue>{};
  final _block = LirBlock();

  LirFunction lower(HirFunction function) {
    for (final instruction in function.body.instructions) {
      _values[instruction] = _block.add(_instruction(instruction));
    }
    switch (function.body.terminator!) {
      case HirReturn():
        _block.end(Return());
      case HirExit(:final code):
        _block
          ..add(Call('exit', _exit, [_values[code]!]))
          ..end(Unreachable());
    }
    // A prefix keeps Dart names apart from system functions.
    return LirFunction('dart.${function.name}', LirSignature([]), [_block]);
  }

  LirInstruction _instruction(HirInstruction instruction) {
    switch (instruction) {
      case HirInt(:final value):
        return ConstInt(value);
      case HirIntBinary(:final operator, :final left, :final right):
        final IntOp op = switch (operator) {
          .add => .add,
          .subtract => .sub,
          .multiply => .mul,
          .and => .and,
          .or => .or,
          .xor => .xor,
        };
        return IntBinary(op, _values[left]!, _values[right]!);
      case HirIntUnary(:final operator, :final operand):
        final value = _values[operand]!;
        return switch (operator) {
          .negate => IntBinary(.sub, _block.add(ConstInt(0)), value),
          .complement => IntBinary(.xor, value, _block.add(ConstInt(-1))),
        };
    }
  }
}
