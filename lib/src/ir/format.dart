import 'dart:convert' show jsonEncode;

import 'block.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// Writes a graph labeled with function-local block and value numbers to [output].
void writeFunction(
  StringSink output,
  FunctionTarget target,
  List<Block> blocks,
) {
  final labels = {for (final (i, b) in blocks.indexed) b: 'b$i'};
  final ids = <Value, int>{};
  String symbol(FunctionTarget t, [ClassType? ownerType]) {
    if (t.enclosing case final outer?) {
      return '${symbol(outer)}::${t.name}@${t.sourceOffset}';
    }
    final prefix = switch (t.kind) {
      .getter || .staticGetter => 'get ',
      .setter || .staticSetter => 'set ',
      _ => '',
    };
    final provenance = t.privateSelectorLibrary;
    final suffix = provenance != null && provenance != t.library
        ? ' [private $provenance]'
        : '';
    return '${t.library}::${t.owner == null ? '' : '${(ownerType ?? t.owner!).dartName}.'}$prefix${t.name}$suffix';
  }

  String global(GlobalVariable slot) =>
      '${slot.library}::${slot.owner == null ? '' : '${slot.owner!.dartName}.'}${slot.name}';
  String typeArgs(Iterable<ValueType> types) =>
      types.isEmpty ? '' : '<${types.map((t) => t.dartName).join(', ')}>';
  String value(Value v) => switch (v) {
    TypeConstant(:final representedType) => 'type ${representedType.dartName}',
    ScalarConstant(value: final String s) => jsonEncode(s),
    ScalarConstant(:final value) => '$value',
    FunctionConstant(
      :final target,
      :final ownerType,
      :final typeArguments,
      :final constructorAlias,
      :final constructorSignature,
    ) =>
      'tearoff ${constructorAlias == null ? symbol(target, ownerType) : "${constructorAlias.$1}::${constructorAlias.$2}.${target.name}"}${typeArgs(typeArguments ?? const [])}${constructorSignature == null ? "" : " as ${constructorSignature.dartName}"}',
    RecordConstant(:final type, :final fields) =>
      'const ${type.dartName}[${fields.map(value).join(', ')}]',
    SequenceConstant(:final type, :final elements) =>
      'const ${type.dartName}[${elements.map(value).join(', ')}]',
    MapConstant(:final type, :final entries) =>
      'const ${type.dartName}{${entries.map((e) => '${value(e.$1)}: ${value(e.$2)}').join(', ')}}',
    ObjectConstant(:final type, :final fields) =>
      'const ${type.dartName}{${fields.entries.map((e) => '${e.key.owner.library}::${e.key.owner.dartName}.${e.key.name}: ${value(e.value)}').join(', ')}}',
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
  String cell(NewCell op) {
    final type = op.type as CellType;
    final state = op.initializer != null
        ? 'lazy ${value(op.initializer!)}'
        : op.initial == null
        ? 'uninitialized'
        : value(op.initial!);
    return '${type.isLate ? 'late ' : ''}${type.isFinal ? 'final ' : ''}cell $state';
  }

  String operation(Instruction op) => switch (op) {
    ListSublist() => 'listSublist ${op.inputs.map(value).join(', ')}',
    MapContainsKey() => 'mapContainsKey ${value(op.map)}, ${value(op.key)}',
    PatternMatchFailure() => 'patternMatchFailure',
    MapEntries() => 'entries ${value(op.map)}',
    CollectionLength() => 'length ${value(op.collection)}',
    CollectionGet() =>
      'collectionGet ${value(op.collection)}, ${value(op.key)}',
    ListSet() =>
      'listSet ${value(op.collection)}, ${value(op.key)}, ${value(op.value)}',
    NewCollection() => 'newCollection ${op.type.dartName}',
    CollectionAdd() =>
      'collectionAdd ${value(op.collection)}, ${value(op.value)}',
    CollectionSpread() =>
      '${op.isMethodCall ? 'collectionAddAll' : 'collectionSpread'} ${value(op.collection)}, ${value(op.source)}',
    MapPut() => 'mapPut ${value(op.map)}, ${value(op.key)}, ${value(op.value)}',
    GetIterator() => 'iterator ${value(op.iterable)}',
    IteratorMoveNext() => 'moveNext ${value(op.iterator)}',
    IteratorCurrent() => 'current ${value(op.iterator)}',
    AssertionFailure() =>
      'assertionFailure${op.message == null ? '' : ' ${value(op.message!)}'}',
    MakeClosure() =>
      'close ${symbol(op.target)}(${op.inputs.map(value).join(', ')})',
    NewCell() => cell(op),
    ReadCell() => 'readCell ${value(op.cell)}',
    CopyCell() => 'copyCell ${value(op.cell)}',
    WriteCell() => 'writeCell ${value(op.cell)}, ${value(op.value)}',
    BindMethod() =>
      'bind ${op.direct ? 'super ' : ''}${value(op.receiver)} ${symbol(op.method)}',
    InstantiateFunction() =>
      'instantiate ${value(op.function)}${typeArgs(op.typeArguments)}',
    FunctionCall() =>
      'callValue ${value(op.function)}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})',
    LoadGlobal() => 'loadGlobal ${global(op.global)}',
    StoreGlobal() => 'storeGlobal ${global(op.global)}, ${value(op.value)}',
    LoadField() =>
      'load ${value(op.receiver)}.${op.field.owner.dartName}::${op.field.name}',
    InstanceCall() =>
      'dispatch ${value(op.receiver)} ${symbol(op.member)}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})',
    DynamicDispatch() =>
      'dynamicDispatch ${value(op.receiver)} ${op.selector.kind.name} '
          '${op.selector.privateLibrary == null ? "" : "${op.selector.privateLibrary}::"}'
          '${op.selector.name}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})',
    MakeInvocation() =>
      'makeInvocation ${op.selector.kind.name} '
          '${op.selector.privateLibrary == null ? "" : "${op.selector.privateLibrary}::"}'
          '${op.selector.name}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})',
    Construct() =>
      'new ${symbol(op.initializer, op.instantiatedType)}(${op.inputs.map(value).join(', ')})',
    StoreField() =>
      'store ${value(op.receiver)}.${op.field.owner.dartName}::${op.field.name}, ${value(op.value)}',
    MakeRecord() =>
      'record ${op.type.dartName}[${op.inputs.map(value).join(', ')}]',
    RecordGet() => 'field ${value(op.record)}[${op.slot}]',
    Equals() =>
      '${value(op.left)} ${op.negated ? '!=' : '=='} ${value(op.right)}',
    ReifyType() => 'reify ${op.template.dartName}',
    ObjectHashCode() =>
      '${op.direct ? 'direct ' : ''}hashCode ${value(op.operand)}',
    TypeTest() =>
      '${value(op.operand)} ${op.negated ? 'is!' : 'is'} ${op.testedType.dartName}',
    TypeView() => 'view ${value(op.operand)} as ${op.type.dartName}',
    TypeCast() => '${value(op.operand)} as ${op.type.dartName}',
    NullCheck() => 'checkNotNull ${value(op.operand)}',
    NumericBinary() =>
      'numeric.${op.operator.name} ${value(op.left)}, ${value(op.right)}',
    Interpolate() => 'interpolate [${op.inputs.map(value).join(', ')}]',
    StringConcat() => 'concat ${value(op.left)}, ${value(op.right)}',
    NumericNegate() => 'negate ${value(op.operand)}',
    IntBinary() => '${op.operator.name} ${value(op.left)}, ${value(op.right)}',
    DirectCall() =>
      'call ${symbol(op.target, op.ownerType)}${typeArgs(op.typeArguments)}(${op.inputs.map(value).join(', ')})',
  };
  String unwind(Jump? handler) =>
      handler == null ? '' : ' unwind ${edge(handler)}';
  final binders = target.typeParameters.isEmpty
      ? ''
      : '<${target.typeParameters.map((p) => '${p.name} extends ${p.bound.dartName}').join(', ')}>';
  output.writeln('${symbol(target)}$binders -> ${target.returnType.dartName}');
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
