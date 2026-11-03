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
  String symbol(FunctionTarget t) {
    final prefix = switch (t.kind) {
      .getter => 'get ',
      .setter => 'set ',
      _ => '',
    };
    return '${t.library}::${t.owner == null ? '' : '${t.owner!.dartName}.'}$prefix${t.name}';
  }

  String value(Value v) => switch (v) {
    ScalarConstant(value: final String s) => jsonEncode(s),
    ScalarConstant(:final value) => '$value',
    FunctionConstant(:final target) => 'tearoff ${symbol(target)}',
    RecordConstant(:final type, :final fields) =>
      'const ${type.dartName}[${fields.map(value).join(', ')}]',
    TestedValue(:final test, :final type) =>
      '${value(test.operand)} as ${type.dartName}',
    UnwindValue() => v == UnwindValue.exception ? 'exception' : 'stackTrace',
    _ => '%${ids.putIfAbsent(v, () => ids.length)}',
  };
  String edge(Jump e) =>
      '${labels[e.target]}(${e.arguments.map(value).join(', ')})';
  String arguments(List<Value> positional, Map<String, Value> named) => [
    ...positional.map(value),
    for (final e in named.entries) '${e.key}: ${value(e.value)}',
  ].join(', ');
  String operation(Instruction op) => switch (op) {
    BindMethod() =>
      'bind ${op.direct ? 'super ' : ''}${value(op.receiver)} ${symbol(op.method)}',
    FunctionCall() =>
      'callValue ${value(op.function)}(${arguments(op.positional, op.named)})',
    LoadField() =>
      'load ${value(op.receiver)}.${op.field.owner.dartName}::${op.field.name}',
    InstanceCall() =>
      'dispatch ${value(op.receiver)} ${symbol(op.member)}(${arguments(op.positional, op.named)})',
    Construct() =>
      'new ${symbol(op.initializer)}(${op.inputs.map(value).join(', ')})',
    StoreField() =>
      'store ${value(op.receiver)}.${op.field.owner.dartName}::${op.field.name}, ${value(op.value)}',
    MakeRecord() =>
      'record ${op.type.dartName}[${op.inputs.map(value).join(', ')}]',
    RecordGet() => 'field ${value(op.record)}[${op.slot}]',
    Equals() =>
      '${value(op.left)} ${op.negated ? '!=' : '=='} ${value(op.right)}',
    TypeTest() =>
      '${value(op.operand)} ${op.negated ? 'is!' : 'is'} ${op.testedType.dartName}',
    TypeCast() => '${value(op.operand)} as ${op.type.dartName}',
    NullCheck() => 'checkNotNull ${value(op.operand)}',
    IntBinary() => '${op.operator.name} ${value(op.left)}, ${value(op.right)}',
    DirectCall() =>
      'call ${symbol(op.target)}(${op.inputs.map(value).join(', ')})',
  };
  String unwind(Jump? handler) =>
      handler == null ? '' : ' unwind ${edge(handler)}';
  output.writeln('${symbol(target)} -> ${target.returnType.dartName}');
  for (final b in blocks) {
    final parameters = b.parameters
        .map((p) => '${value(p)}: ${p.type.dartName}')
        .join(', ');
    output.writeln('${labels[b]}($parameters):');
    for (final op in b.instructions) {
      output.writeln('  ${value(op)} = ${operation(op)}');
    }
    output.writeln(switch (b.end) {
      Return(value: final v?) => '  return ${value(v)}',
      Return() => '  return',
      Throw(:final exception, stackTrace: final trace?, :final onThrow) =>
        '  rethrow ${value(exception)}, ${value(trace)}${unwind(onThrow)}',
      Throw(:final exception, :final onThrow) =>
        '  throw ${value(exception)}${unwind(onThrow)}',
      ExhaustivenessFailure(:final onThrow) =>
        '  exhaustivenessError${unwind(onThrow)}',
      Invoke(operation: final op, :final onReturn, :final onThrow) =>
        '  ${value(op)} = invoke ${operation(op)}${onReturn == null ? '' : ' return ${edge(onReturn)}'}${unwind(onThrow)}',
      Unreachable(:final cause) => '  unreachable ${value(cause)}',
      final Jump j => '  jump ${edge(j)}',
      Branch(:final condition, :final ifTrue, :final ifFalse) =>
        '  branch ${value(condition)}, ${edge(ifTrue)}, ${edge(ifFalse)}',
    });
  }
}
