import 'block.dart';
import 'instruction.dart';
import 'module.dart';
import 'value.dart';

/// Readable text for a whole module.
String printModule(LirModule module) => [
  for (final data in module.data)
    'data ${data.name}: ${data.bytes.length} bytes'
        '${data.writable ? ', writable' : ''}',
  for (final external in module.externals)
    'external ${external.name}${external.signature}',
  ...module.functions.map(printFunction),
].join('\n');

/// Readable text for one function, stable across runs.
String printFunction(LirFunction function) => _Printer(function).run();

final class _Printer(final LirFunction function) {
  final _names = <LirValue, String>{};
  final _blocks = <LirBlock, String>{};

  String run() {
    for (final (i, block) in function.blocks.indexed) {
      _blocks[block] = 'b$i';
      for (final value in [...block.parameters, ...block.instructions]) {
        if (value.type != null) _names[value] = 'v${_names.length}';
      }
    }
    final lines = ['func ${function.name}${function.signature} {'];
    for (final block in function.blocks) {
      final parameters = block.parameters
          .map((p) => '${_name(p)}: ${p.type.name}')
          .join(', ');
      lines.add('${_blocks[block]}($parameters):');
      for (final instruction in block.instructions) {
        final result = instruction.type == null
            ? ''
            : '${_name(instruction)} = ';
        lines.add('  $result${_instruction(instruction)}');
      }
      final end = block.terminator;
      lines.add('  ${end == null ? '<no terminator>' : _terminator(end)}');
    }
    return [...lines, '}'].join('\n');
  }

  String _name(LirValue value) => _names[value] ?? '<undefined>';

  String _list(Iterable<LirValue> values) => values.map(_name).join(', ');

  String _place(LirValue base, int offset, LirValue? index) =>
      '[${_name(base)}${index == null ? '' : ' + ${_name(index)}'}'
      '${offset == 0 ? '' : ' + $offset'}]';

  String _instruction(LirInstruction instruction) => switch (instruction) {
    ConstInt(:final value) => 'int $value',
    ConstFloat(:final value) => 'float $value',
    ConstNull() => 'null',
    SymbolAddress(:final symbol) => 'address $symbol',
    IntBinary(:final op, :final inputs) => 'int.${op.name} ${_list(inputs)}',
    FloatBinary(:final op, :final inputs) =>
      'float.${op.name} ${_list(inputs)}',
    FloatUnary(:final op, :final inputs) => 'float.${op.name} ${_list(inputs)}',
    Compare(:final relation, :final left, :final inputs) =>
      '${left.type?.name}.${relation.name} ${_list(inputs)}',
    Convert(:final op, :final inputs) => '${op.name} ${_list(inputs)}',
    PtrAdd(:final inputs) => 'ptr.add ${_list(inputs)}',
    Load(:final width, :final base, :final offset, :final index) =>
      'load.${width.name} ${_place(base, offset, index)}',
    Store(
      :final width,
      :final base,
      :final offset,
      :final index,
      :final value,
    ) =>
      'store.${width.name} ${_place(base, offset, index)}, ${_name(value)}',
    Call(:final symbol, :final arguments) =>
      'call $symbol(${_list(arguments)})',
    CallIndirect(:final address, :final signature, :final arguments) =>
      'call ${_name(address)} $signature(${_list(arguments)})',
    Alloc(:final size) => 'alloc ${_name(size)}',
  };

  String _edge(LirEdge edge) =>
      '${_blocks[edge.target] ?? '<foreign>'}(${_list(edge.arguments)})';

  String _terminator(LirTerminator end) => switch (end) {
    Jump(:final edge) => 'jump ${_edge(edge)}',
    Branch(:final condition, :final ifTrue, :final ifFalse) =>
      'branch ${_name(condition)}, ${_edge(ifTrue)}, ${_edge(ifFalse)}',
    Return(:final inputs) => 'return ${_list(inputs)}'.trimRight(),
    Throw(:final inputs) => 'throw ${_list(inputs)}',
    Invoke(:final call, :final onReturn, :final onThrow) =>
      'invoke ${_instruction(call)}, ${_edge(onReturn)}, throw ${_edge(onThrow)}',
    Unreachable() => 'unreachable',
  };
}
