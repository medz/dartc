import 'block.dart';
import 'class.dart';
import 'global.dart';
import 'instruction.dart';
import 'module.dart';
import 'value.dart';

/// Readable text for a program, stable across runs.
String printHir(HirModule module) => [
  for (final class_ in module.classes) _class(class_),
  for (final HirGlobal(:type, :name, :initial) in module.globals)
    'global ${type.dartName} $name = $initial',
  for (final MapEntry(key: selector, value: entries) in module.dispatch.entries)
    'dispatch ${selector.name}: ${entries.entries.map(_entry).join(', ')}',
  for (final MapEntry(key: test, value: passing) in module.tests.entries)
    'test ${test.name}: ${passing.map((class_) => class_.name).join(', ')}',
  for (final function in module.functions) _Printer(function).run(),
].join('\n');

String _class(HirClass class_) {
  final superclass = class_.superclass;
  final parent = superclass == null ? '' : ' extends ${superclass.name}';
  final fields = class_.ownFields.map(
    (field) => '${field.type.dartName} ${field.name}; ',
  );
  final elements = class_.elements == null
      ? ''
      : ' of ${class_.elements!.name}';
  return 'class ${class_.name}$parent$elements { ${fields.join()}}';
}

String _entry(MapEntry<HirClass, HirFunction> entry) =>
    '${entry.key.name} => ${entry.value.name}';

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
    HirNull() => 'null',
    HirNew(:final target) => 'new ${target.name}',
    HirBox(:final target, :final value) => '${target.name} ${_name(value)}',
    HirUnbox(:final field, :final object) =>
      'unbox ${_name(object)}.${field.name}',
    HirStatic(:final object) => 'const $object',
    HirLoadGlobal(:final global) => global.name,
    HirStoreGlobal(:final global, :final value) =>
      '${global.name} = ${_name(value)}',
    HirMachine(:final op, :final arguments) =>
      '${op.name}(${_list(arguments)})',
    HirLoad(:final field, :final object) => '${_name(object)}.${field.name}',
    HirStore(:final field, :final object, :final value) =>
      '${_name(object)}.${field.name} = ${_name(value)}',
    HirVirtualCall(:final selector, :final receiver, :final arguments) =>
      '${_name(receiver)}->${selector.name}(${_list(arguments)})',
    HirIsInstance(:final test, :final object) =>
      '${_name(object)} is ${test.name}',
    HirHasClass(:final target, :final object) =>
      '${_name(object)} is exactly ${target.name}',
    HirNewArray(:final target, :final length) =>
      'new ${target.name}[${_name(length)}]',
    HirLength(:final array) => '${_name(array)}.length',
    HirLoadElement(:final element, :final array, :final index) =>
      '${_name(array)}[${element.name} ${_name(index)}]',
    HirStoreElement(:final element, :final array, :final index, :final value) =>
      '${_name(array)}[${element.name} ${_name(index)}] = ${_name(value)}',
    HirNativeFunction(:final name) => 'native $name',
    HirClassNumber(:final target) => 'number ${target.name}',
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
    HirThrow(:final inputs) => 'throw ${_list(inputs)}',
    HirInvoke(:final call, :final onReturn, :final onThrow) =>
      'invoke ${_instruction(call)}, ${_edge(onReturn)}, '
          'throw ${_edge(onThrow)}',
    HirExit(:final code) => 'exit ${_name(code)}',
    HirUnreachable() => 'unreachable',
  };
}
