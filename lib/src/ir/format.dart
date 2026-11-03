import 'dart:convert' show jsonEncode;

import 'block.dart';
import 'signature.dart';
import 'value.dart';

/// Writes a graph labeled with function-local block and value numbers to [output].
void writeFunction(
  StringSink output,
  FunctionTarget target,
  List<Block> blocks,
) {
  final labels = {for (final (i, b) in blocks.indexed) b: 'b$i'};
  final ids = <Value, int>{};
  String value(Value v) => switch (v) {
    Constant(value: final String s) => jsonEncode(s),
    Constant(:final value) => '$value',
    TestedValue(:final test, :final type) =>
      '${value(test.operand)} as ${type.dartName}',
    _ => '%${ids.putIfAbsent(v, () => ids.length)}',
  };
  String edge(Jump e) =>
      '${labels[e.target]}(${e.arguments.map(value).join(', ')})';
  String symbol(FunctionTarget t) => '${t.library}::${t.name}';
  output.writeln('${symbol(target)} -> ${target.returnType.dartName}');
  for (final b in blocks) {
    final parameters = b.parameters
        .map((p) => '${value(p)}: ${p.type.dartName}')
        .join(', ');
    output.writeln('${labels[b]}($parameters):');
    for (final op in b.instructions) {
      final rhs = switch (op) {
        ScalarEquals() =>
          '${value(op.left)} ${op.negated ? '!=' : '=='} ${value(op.right)}',
        TypeTest() =>
          '${value(op.operand)} ${op.negated ? 'is!' : 'is'} ${op.testedType.dartName}',
        TypeCast() => '${value(op.operand)} as ${op.type.dartName}',
        NullCheck() => 'checkNotNull ${value(op.operand)}',
        IntBinary() =>
          '${op.operator.name} ${value(op.left)}, ${value(op.right)}',
        DirectCall() =>
          'call ${symbol(op.target)}(${op.inputs.map(value).join(', ')})',
      };
      output.writeln('  ${value(op)} = $rhs');
    }
    output.writeln(switch (b.end) {
      Return(value: final v?) => '  return ${value(v)}',
      Return() => '  return',
      Throw(:final exception) => '  throw ${value(exception)}',
      ExhaustivenessFailure() => '  exhaustivenessError',
      Unreachable(:final cause) => '  unreachable ${value(cause)}',
      final Jump j => '  jump ${edge(j)}',
      Branch(:final condition, :final ifTrue, :final ifFalse) =>
        '  branch ${value(condition)}, ${edge(ifTrue)}, ${edge(ifFalse)}',
    });
  }
}
