import 'block.dart';
import 'signature.dart';
import 'value.dart';

/// Writes a graph labeled with function-local block and value numbers to [output].
void writeFunction(
  StringSink output,
  FunctionTarget target,
  List<Block> blocks,
) {
  String type(ValueType t) => switch (t) {
    .integer => 'int',
    .boolean => 'bool',
    .voidType => 'void',
  };
  final labels = {for (final (i, b) in blocks.indexed) b: 'b$i'};
  final ids = <Value, int>{};
  String value(Value v) =>
      v is Constant ? '${v.value}' : '%${ids.putIfAbsent(v, () => ids.length)}';
  String edge(Jump e) =>
      '${labels[e.target]}(${e.arguments.map(value).join(', ')})';
  String symbol(FunctionTarget t) => '${t.library}::${t.name}';
  output.writeln('${symbol(target)} -> ${type(target.returnType)}');
  for (final b in blocks) {
    final parameters = b.parameters
        .map((p) => '${value(p)}: ${type(p.type)}')
        .join(', ');
    output.writeln('${labels[b]}($parameters):');
    for (final op in b.instructions) {
      final rhs = switch (op) {
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
      final Jump j => '  jump ${edge(j)}',
      Branch(:final condition, :final ifTrue, :final ifFalse) =>
        '  branch ${value(condition)}, ${edge(ifTrue)}, ${edge(ifFalse)}',
    });
  }
}
