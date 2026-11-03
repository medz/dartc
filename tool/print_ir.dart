import 'dart:io';

import 'package:dartc/src/_internal/checked_libraries.dart';
import 'package:dartc/src/_internal/ir/ir.dart';
import 'package:dartc/src/_internal/lowering/dart_lowering.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || !File(args.single).existsSync()) {
    stderr.writeln('Usage: dart run tool/print_ir.dart <library.dart>');
    exitCode = 64;
    return;
  }
  try {
    for (final function in await CheckedLibraries.read(
      args,
      DartLowering.lower,
    )) {
      stdout.write(_format(function));
    }
  } on FormatException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on UnsupportedError catch (error) {
    stderr.writeln(error.message);
    exitCode = 1;
  }
}

String _format(IrFunction function) {
  String type(ValueType t) => switch (t) {
    .integer => 'int',
    .boolean => 'bool',
    .voidType => 'void',
  };
  final labels = {for (final (i, b) in function.blocks.indexed) b: 'b$i'};
  final ids = <Value, int>{};
  String value(Value v) =>
      v is Constant ? '${v.value}' : '%${ids.putIfAbsent(v, () => ids.length)}';
  String edge(Jump e) =>
      '${labels[e.target]}(${e.arguments.map(value).join(', ')})';
  String symbol(FunctionTarget t) => '${t.library}::${t.name}';
  final text = StringBuffer()
    ..writeln(
      '${symbol(function.target)} -> ${type(function.target.returnType)}',
    );
  for (final b in function.blocks) {
    final parameters = b.parameters
        .map((p) => '${value(p)}: ${type(p.type)}')
        .join(', ');
    text.writeln('${labels[b]}($parameters):');
    for (final op in b.instructions) {
      final rhs = switch (op) {
        IntBinary() =>
          '${op.operator.name} ${value(op.left)}, ${value(op.right)}',
        DirectCall() =>
          'call ${symbol(op.target)}(${op.inputs.map(value).join(', ')})',
      };
      text.writeln('  ${value(op)} = $rhs');
    }
    text.writeln(switch (b.end) {
      Return(value: final v?) => '  return ${value(v)}',
      Return() => '  return',
      final Jump j => '  jump ${edge(j)}',
      Branch(:final condition, :final ifTrue, :final ifFalse) =>
        '  branch ${value(condition)}, ${edge(ifTrue)}, ${edge(ifFalse)}',
    });
  }
  return text.toString();
}
