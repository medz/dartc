import 'package:dartc/graph.dart';
import 'package:dartc/hir.dart';
import 'package:dartc/lir.dart';

import 'operators.dart';
import 'system.dart';

LirType _typeOf(HirType type) => switch (type) {
  .integer || .boolean => .i64,
  .float => .f64,
};

/// The machine-level signature of [function].
LirSignature signatureOf(HirCallable function) => LirSignature(
  function.parameters.map(_typeOf),
  function.result == null ? null : _typeOf(function.result!),
);

/// Lowers one function, block by block.
final class FunctionLowering(
  final HirFunction function,
  final Map<HirCallable, String> symbols,
) {
  final _values = <HirValue, LirValue>{};
  final _blocks = <HirBlock, LirBlock>{};

  LirFunction lower() {
    for (final block in function.blocks) {
      final lowered = LirBlock(block.parameters.map((p) => _typeOf(p.type)));
      _blocks[block] = lowered;
      for (final (i, parameter) in block.parameters.indexed) {
        _values[parameter] = lowered.parameters[i];
      }
    }
    // In this order, definitions come before the uses they dominate.
    final order = reversePostorder(
      function.entry,
      (block) => block.terminator!.edges.map((edge) => edge.target),
    );
    for (final block in order) {
      final lowered = _blocks[block]!;
      for (final instruction in block.instructions) {
        _values[instruction] = _instruction(lowered, instruction);
      }
      lowered.end(_terminator(lowered, block.terminator!));
    }
    return LirFunction(
      symbols[function]!,
      signatureOf(function),
      _blocks.values,
    );
  }

  LirValue _value(HirValue value) => _values[value]!;

  LirValue _instruction(LirBlock block, HirInstruction instruction) {
    final operators = OperatorLowering(block);
    switch (instruction) {
      case HirConst(:final Object value):
        return block.add(switch (value) {
          int() => ConstInt(value),
          double() => ConstFloat(value),
          _ => ConstInt(value == true ? 1 : 0),
        });
      case HirIntBinary(:final operator, :final left, :final right):
        final constant = right is HirConst ? right.value as int : null;
        return operators.integer(
          operator,
          _value(left),
          _value(right),
          constant,
        );
      case HirFloatBinary(:final operator, :final left, :final right):
        return operators.float(operator, _value(left), _value(right));
      case HirBoolBinary(:final operator, :final left, :final right):
        return operators.boolean(operator, _value(left), _value(right));
      case HirUnary(:final operator, :final operand):
        return operators.unary(operator, _value(operand));
      case HirCompare(:final relation, :final left, :final right):
        return operators.compare(relation, _value(left), _value(right));
      case HirCall(:final target, :final arguments):
        return block.add(
          Call(symbols[target]!, signatureOf(target), arguments.map(_value)),
        );
    }
  }

  LirEdge _edge(HirEdge edge) =>
      LirEdge(_blocks[edge.target]!, edge.arguments.map(_value));

  LirTerminator _terminator(LirBlock block, HirTerminator end) {
    switch (end) {
      case HirJump(:final edge):
        return Jump(_edge(edge));
      case HirBranch(:final condition, :final ifTrue, :final ifFalse):
        return Branch(_value(condition), _edge(ifTrue), _edge(ifFalse));
      case HirReturn(:final value):
        return Return(value == null ? null : _value(value));
      case HirExit(:final code):
        block.add(Call('exit', exitSignature, [_value(code)]));
        return Unreachable();
      case HirUnreachable():
        return Unreachable();
    }
  }
}
