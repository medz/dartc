import 'block.dart';
import 'instruction.dart';
import 'module.dart';
import 'value.dart';

/// Readable text for a program, stable across runs.
String printHir(HirModule module) =>
    module.functions.map((function) => _Printer(function).run()).join('\n');

final class _Printer(final HirFunction function) {
  final _names = <HirValue, String>{};
  final _blocks = <HirBlock, String>{};

  String run() {
    for (final (i, block) in function.blocks.indexed) {
      _blocks[block] = 'b$i';
      for (final value in [...block.parameters, ...block.instructions]) {
        if (value.type != null) _names[value] = 'v${_names.length}';
      }
    }
    final result = function.result?.dartName ?? 'void';
    final lines = ['$result ${function.name} {'];
    for (final block in function.blocks) {
      final parameters = block.parameters
          .map((p) => '${p.type.dartName} ${_name(p)}')
          .join(', ');
      lines.add('${_blocks[block]}($parameters):');
      for (final instruction in block.instructions) {
        final name = instruction.type == null ? '' : '${_name(instruction)} = ';
        lines.add('  $name${_instruction(instruction)}');
      }
      final end = block.terminator;
      lines.add('  ${end == null ? '<no terminator>' : _terminator(end)}');
    }
    return [...lines, '}'].join('\n');
  }

  String _name(HirValue value) => _names[value] ?? '<undefined>';

  String _list(Iterable<HirValue> values) => values.map(_name).join(', ');

  String _infix(String symbol, HirValue left, HirValue right) =>
      '${_name(left)} $symbol ${_name(right)}';

  String _instruction(HirInstruction instruction) => switch (instruction) {
    HirConst(:final value) => '$value',
    HirIntBinary(:final operator, :final left, :final right) => _infix(
      operator.symbol,
      left,
      right,
    ),
    HirFloatBinary(:final operator, :final left, :final right) => _infix(
      operator.symbol,
      left,
      right,
    ),
    HirBoolBinary(:final operator, :final left, :final right) => _infix(
      operator.symbol,
      left,
      right,
    ),
    HirCompare(:final relation, :final left, :final right) => _infix(
      relation.symbol,
      left,
      right,
    ),
    HirUnary(:final operator, :final operand) =>
      '${operator.symbol}${_name(operand)}',
    HirCall(:final target, :final arguments) =>
      '${target.name}(${_list(arguments)})',
  };

  String _edge(HirEdge edge) =>
      '${_blocks[edge.target] ?? '<foreign>'}(${_list(edge.arguments)})';

  String _terminator(HirTerminator end) => switch (end) {
    HirJump(:final edge) => 'jump ${_edge(edge)}',
    HirBranch(:final condition, :final ifTrue, :final ifFalse) =>
      'branch ${_name(condition)}, ${_edge(ifTrue)}, ${_edge(ifFalse)}',
    HirReturn(:final inputs) => 'return ${_list(inputs)}'.trimRight(),
    HirExit(:final code) => 'exit ${_name(code)}',
    HirUnreachable() => 'unreachable',
  };
}
