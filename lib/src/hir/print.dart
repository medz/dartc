import 'instruction.dart';
import 'module.dart';

/// Readable text for a program, stable across runs.
String printHir(HirModule module) {
  final function = module.main;
  final names = <HirInstruction, String>{};
  String name(HirInstruction value) => names[value] ?? '<undefined>';
  final lines = ['${function.name}() {'];
  for (final instruction in function.body.instructions) {
    final text = switch (instruction) {
      HirInt(:final value) => '$value',
      HirIntBinary(:final operator, :final left, :final right) =>
        '${name(left)} ${operator.symbol} ${name(right)}',
      HirIntUnary(:final operator, :final operand) =>
        '${operator.symbol}${name(operand)}',
    };
    names[instruction] = 'v${names.length}';
    lines.add('  ${name(instruction)} = $text');
  }
  lines.add(switch (function.body.terminator) {
    HirReturn() => '  return',
    HirExit(:final code) => '  exit ${name(code)}',
    null => '  <no terminator>',
  });
  return [...lines, '}'].join('\n');
}
