import 'dart:convert' show jsonEncode;

import 'block.dart';
import 'native_data.dart';
import 'module_object.dart';
import 'signature.dart';
import 'type.dart';
import 'value.dart';

/// Writes a graph labeled with function-local block and value numbers to [output].
void writeFunction(
  StringSink output,
  FunctionTarget target,
  List<Block> blocks, {
  required FunctionBodyKind bodyKind,
  ValueType? yieldType,
  ValueType? completionType,
}) {
  final labels = {for (final (i, b) in blocks.indexed) b: 'b$i'};
  final ids = <Value, int>{};
  final nativeData = <NativeData, int>{};
  final moduleObjects = <ModuleObject, int>{};
  String symbol(FunctionTarget t, [ClassType? ownerType]) {
    if (t.enclosing case final outer?) {
      return '${symbol(outer)}::${t.name}@${t.sourceOffset}';
    }
    final prefix = switch (t.kind) {
      .getter || .staticGetter => 'get ',
      .setter || .staticSetter => 'set ',
      _ => '',
    };
    final provenance = t.privateSelectorScope;
    final suffix = provenance != null && provenance != t.library
        ? ' [private $provenance]'
        : '';
    return '${t.library ?? '<generated>'}::${t.owner == null ? '' : '${(ownerType ?? t.owner!).dartName}.'}$prefix${t.name}$suffix';
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
      :final constructorTypeArguments,
      :final invocationEntry,
    ) =>
      'tearoff ${constructorAlias == null ? symbol(target, ownerType) : "${constructorAlias.$1}::${constructorAlias.$2}.${target.name}"}${typeArgs(typeArguments ?? const [])}${constructorSignature == null ? "" : " as ${constructorSignature.dartName}"}${constructorTypeArguments == null ? "" : " => ${symbol(target)}${typeArgs(constructorTypeArguments)}"}${invocationEntry == null ? "" : " via ${symbol(invocationEntry)}"}',
    RecordConstant(:final type, :final fields) =>
      'const ${type.dartName}[${fields.map(value).join(', ')}]',
    SequenceConstant(:final type, :final elements) =>
      'const ${type.dartName}[${elements.map(value).join(', ')}]',
    MapConstant(:final type, :final entries) =>
      'const ${type.dartName}{${entries.map((e) => '${value(e.$1)}: ${value(e.$2)}').join(', ')}}',
    ObjectConstant(:final type, :final fields, :final payload) =>
      'const ${type.dartName}{${fields.entries.map((e) => '${e.key.owner.library}::${e.key.owner.dartName}.${e.key.name}: ${value(e.value)}').join(', ')}}${payload.isEmpty ? '' : '[${payload.map(value).join(', ')}]'}',
    TestedValue(:final test, :final type) =>
      '${value(test.operand)} as ${type.dartName}',
    CallFrameValue(:final isReturnAddress) =>
      isReturnAddress ? 'call.returnAddress' : 'call.stackPointer',
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
    CaptureStackTrace() => 'captureStackTrace',
    FrameValue(:final kind) => 'frame.${kind.name}',
    StackMapAddress(contextFreeOnly: true) => 'contextFreeStackMapAddress',
    StackMapAddress() => 'stackMapAddress',
    ModuleRootsAddress() => 'moduleRootsAddress',
    ReadNativeContext() => 'readNativeContext',
    BindNativeContext(:final address) => 'bindNativeContext ${value(address)}',
    ObjectDescriptorAddress(:final declaration) =>
      'descriptor ${declaration.dartName}',
    LoadLibrary(:final reference) =>
      'loadLibrary ${reference.unit}::${reference.prefix} -> ${reference.library}',
    CheckLibraryLoaded(:final reference) =>
      'checkLibraryLoaded ${reference.unit}::${reference.prefix} -> ${reference.library}',
    ListSublist() => 'listSublist ${op.inputs.map(value).join(', ')}',
    MapContainsKey() => 'mapContainsKey ${value(op.map)}, ${value(op.key)}',
    PatternMatchFailure() => 'patternMatchFailure',
    MapEntries() => 'entries ${value(op.map)}',
    CollectionLength() => 'length ${value(op.collection)}',
    CollectionGet() =>
      'collectionGet ${value(op.collection)}, ${value(op.key)}',
    ListSet() =>
      'listSet ${value(op.collection)}, ${value(op.key)}, ${value(op.value)}',
    NewCollection() =>
      'newCollection ${op.type.dartName}${op.growable == null ? '' : ', growable: ${value(op.growable!)}'}',
    ListFilled() =>
      'listFilled ${op.type.dartName} ${op.inputs.map(value).join(', ')}',
    ListFrom() =>
      'listFrom ${op.type.dartName} ${op.inputs.map(value).join(', ')}',
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
    CheckedTypeArgument() =>
      'checkTypeArgument ${op.parameter.name} ${value(op.argument)}${op.implementation == null ? '' : ' via ${symbol(op.implementation!)}'}',
    ReadFunctionTypeArgument() =>
      'functionTypeArgument ${value(op.function)}, ${op.source.name}.${op.parameter.name}',
    ReadFunctionEnvironment() =>
      'functionEnvironment ${value(op.function)} ${symbol(op.source)} ${op.capture ?? 'origin'}',
    NewCell() => cell(op),
    ReadCell() => 'readCell ${value(op.cell)}',
    CopyCell() => 'copyCell ${value(op.cell)}',
    WriteCell() => 'writeCell ${value(op.cell)}, ${value(op.value)}',
    BindMethod() =>
      'bind ${op.direct ? 'super ' : ''}${value(op.receiver)} ${symbol(op.method)}${op.entryBinding == null ? '' : ' entries(${op.entryBinding!.entries.values.map(symbol).join(', ')})'}',
    InstantiateFunction() =>
      'instantiate ${value(op.function)}${typeArgs(op.typeArguments)}',
    InstantiateFunctionFrom() =>
      'instantiate ${value(op.function)} from ${value(op.instance)} as ${op.declaration.dartName}',
    FunctionCall() =>
      'callValue ${value(op.function)}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})'
          '${op.target == null ? "" : " target ${symbol(op.target!)}"}'
          '${op.entryBinding == null ? "" : " entries[${op.entryBinding!.shape.slot}] {${op.entryBinding!.entries.entries.map((entry) => '${symbol(entry.key)}: ${symbol(entry.value)}').join(', ')}}"}',
    LoadGlobal() => 'loadGlobal ${global(op.global)}',
    NewPayload() => 'payload ${op.type.dartName} ${value(op.bytes)}',
    NativeView() =>
      'nativeView ${op.type.dartName} ${op.address == null ? "new" : value(op.address!)} copy=${op.copy} owner=${value(op.owner)}',
    NativeLocalStorage(:final storage, :final zeroInitialize) =>
      'nativeLocalStorage $storage zero=$zeroInitialize',
    NativeAddress() => 'nativeAddress ${value(op.view)}',
    FloatBitCast() => 'floatBits${op.width} ${value(op.operand)}',
    NativeSize() => 'nativeSize ${op.nativeType}',
    NativeSymbolAddress(:final reference) =>
      'nativeSymbol ${reference.assetId}::${reference.symbol}',
    NativeDataAddress(:final declaration) =>
      'nativeData${nativeData.putIfAbsent(declaration, () => nativeData.length)} bytes=${declaration.bytes.length} align=${declaration.alignment} writable=${declaration.writable}',
    FunctionEntryTableAddress(:final target) => 'functionEntries ${symbol(target)}',
    CellStorageView(:final backing) => 'cellStorageView ${value(backing)}',
    CellStorageReference(:final cell) => 'cellStorageReference ${value(cell)}',
    CellReference(:final cell) => 'cellReference ${value(cell)}',
    InitializeStorageField(:final field, :final destination, :final source) =>
      'initializeStorageField ${field.name} ${value(destination)} ${value(source)}',
    CallableReference(:final function) => 'callableReference ${value(function)}',
    ModuleObjectReference(:final declaration) =>
      'moduleObject${moduleObjects.putIfAbsent(declaration, () => moduleObjects.length)} ${declaration.type.dartName} {${declaration.initialFields.entries.map((entry) => '${entry.key.name}: ${value(entry.value)}').join(', ')}}',
    NativeCallbackAddress(:final target) =>
      'nativeCallback ${symbol(switch (target) {
        StaticCallbackTarget(:final function) => function,
        ClosureCallbackTarget(:final lookup) => lookup,
      })} ${target.signature} onError=${target.exceptionalReturn == null ? "zero" : value(target.exceptionalReturn!)}',
    NativeFieldOffset() => 'nativeFieldOffset ${op.owner} ${op.index}',
    CopyNative() =>
      'copyNative ${op.nativeType} ${value(op.destination)}, ${value(op.source)}',
    KeepAlive() => 'keepAlive ${value(op.value)}',
    PointerFromAddress() => 'pointerFromAddress ${value(op.address)}',
    ReferenceAddress() => 'referenceAddress ${value(op.object)}',
    ReferenceFromAddress() => 'referenceFromAddress ${value(op.address)}',
    ManagedStorageAllocation() => 'allocateStorage ${op.type.dartName} ${op.inputs.map(value).join(" ")}',
    AllocatedObject() =>
      'allocatedObject ${op.type.dartName} ${value(op.address)}, ${value(op.payloadBytes)}',
    PointerAddress() => 'pointerAddress ${value(op.pointer)}',
    PointerOffset() => 'pointerOffset ${value(op.pointer)}, ${value(op.index)}',
    LoadNative() => 'loadNative ${op.nativeType} ${value(op.address)}',
    LoadObjectData() =>
      'loadObjectData ${op.nativeType} ${value(op.object)}, ${value(op.byteOffset)}',
    StoreObjectData() =>
      'storeObjectData ${op.nativeType} ${value(op.object)}, ${value(op.byteOffset)}, ${value(op.value)}',
    LoadObjectReference() =>
      'loadObjectReference ${op.inputs.map(value).join(', ')}',
    StoreObjectReference() =>
      'storeObjectReference ${op.inputs.map(value).join(', ')}',
    StoreNative() =>
      'storeNative ${op.nativeType} ${value(op.address)}, ${value(op.value)}',
    StoreGlobal() => 'storeGlobal ${global(op.global)}, ${value(op.value)}',
    LoadField() =>
      'load ${value(op.receiver)}.${op.field.owner.dartName}::${op.field.name}',
    InstanceCall() =>
      'dispatch ${value(op.receiver)} ${symbol(op.member)}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})',
    DynamicDispatch() =>
      'dynamicDispatch ${value(op.receiver)} ${op.selector.kind.name} '
          '${op.selector.privateScope == null ? "" : "${op.selector.privateScope}::"}'
          '${op.selector.name}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})'
          '${op.failure == null ? "" : " otherwise ${symbol(op.failure!)}"}',
    MakeInvocation() =>
      'makeInvocation ${op.selector.kind.name} '
          '${op.selector.privateScope == null ? "" : "${op.selector.privateScope}::"}'
          '${op.selector.name}${typeArgs(op.typeArguments)}(${arguments(op.positional, op.named)})',
    InitializeObject(:final initializer, :final inputs) =>
      'initialize ${symbol(initializer)}(${inputs.map(value).join(', ')})',
    Construct() =>
      'new ${symbol(op.initializer, op.instantiatedType)}(${op.inputs.map(value).join(', ')})',
    StoreField() =>
      'store ${value(op.receiver)}.${op.field.owner.dartName}::${op.field.name}, ${value(op.value)}',
    MakeRecord() =>
      'record ${op.type.dartName}[${op.inputs.map(value).join(', ')}]',
    RecordGet() => 'field ${value(op.record)}[${op.slot}]',
    Equals() =>
      '${value(op.left)} ${op.negated ? '!=' : '=='} ${value(op.right)}',
    Identical() => 'identical ${value(op.left)}, ${value(op.right)}',
    ReifyType() => 'reify ${op.template.dartName}',
    ObjectRuntimeType() =>
      '${op.direct ? 'direct ' : ''}runtimeType ${value(op.operand)}',
    ObjectClassName(:final operand) => 'class-name ${value(operand)}',
    ObjectHashCode() =>
      '${op.direct ? 'direct ' : ''}hashCode ${value(op.operand)}',
    TypeTest() =>
      '${value(op.operand)} ${op.negated ? 'is!' : 'is'} ${op.testedType.dartName}',
    MaterializeValue() => 'materialize ${value(op.value)}',
    MaterializedValue() =>
      'materialized ${value(op.value)} in ${value(op.backing)}',
    ConstantCarrier() => 'constantCarrier ${value(op.value)}',
    ProjectValue() => 'project ${value(op.value)}',
    TypeView() => 'view ${value(op.operand)} as ${op.type.dartName}',
    UncheckedCast() => 'unchecked ${value(op.operand)} as ${op.type.dartName}',
    TypeCast() => '${value(op.operand)} as ${op.type.dartName}',
    NullCheck() => 'checkNotNull ${value(op.operand)}',
    NumericBinary() =>
      'numeric.${op.operator.name} ${value(op.left)}, ${value(op.right)}',
    StringConcat() => 'concat ${value(op.left)}, ${value(op.right)}',
    StringLength() => 'stringLength ${value(op.string)}',
    StringFromCharCode() => 'stringFromCharCode ${value(op.code)}',
    StringFromCharCodes() =>
      'stringFromCharCodes ${value(op.codes)}, ${value(op.start)}, ${value(op.end)}',
    StringCodeUnitAt() => 'codeUnitAt ${value(op.string)}, ${value(op.index)}',
    NumericNegate() => 'negate ${value(op.operand)}',
    NumericToDouble() => 'toDouble ${value(op.operand)}',
    NumericToInt() =>
      '${op.rounding.name}${op.checked ? '' : '.unchecked'} ${value(op.operand)}',
    NumericRoundToDouble() =>
      '${op.rounding.name}ToDouble ${value(op.operand)}',
    NumericSquareRoot() => 'sqrt ${value(op.operand)}',
    IntBinary() =>
      '${op.operator.name}${op.checked ? '' : '.unchecked'} ${value(op.left)}, ${value(op.right)}',
    DirectCall() =>
      'call ${symbol(op.target, op.ownerType)}${typeArgs(op.typeArguments)}(${op.inputs.map(value).join(', ')})',
    RawNativeCall() =>
      'callNativeRaw${op.isLeaf ? ' leaf' : ''} ${value(op.address)}(${op.arguments.map(value).join(', ')})${op.resultStorage == null ? '' : ' into ${value(op.resultStorage!)}'}',
    NativeCall() =>
      'callNative${op.isLeaf ? ' leaf' : ''} ${value(op.pointer)}(${op.arguments.map(value).join(', ')})${op.borrowedOwners.isEmpty ? '' : ' borrow ${op.borrowedOwners.entries.map((e) => '${e.key}:${value(e.value)}').join(', ')}'}',
  };
  String unwind(Jump? handler) =>
      handler == null ? '' : ' unwind ${edge(handler)}';
  final binders = target.typeParameters.isEmpty
      ? ''
      : '<${target.typeParameters.map((p) => '${p.name} extends ${p.bound.dartName}').join(', ')}>';
  output.writeln(
    '${symbol(target)}$binders -> ${target.returnType.dartName}'
    '${yieldType == null ? '' : ' ${bodyKind == .asyncGenerator ? 'async' : 'sync'}*<${yieldType.dartName}>'}'
    '${completionType == null ? '' : ' async<${completionType.dartName}>'}',
  );
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
      Await(:final operand, :final result, :final onResume, :final onThrow) =>
        '  ${value(result)}: ${result.type.dartName} = await ${value(operand)}'
            '${onResume == null ? '' : ' resume ${edge(onResume)}'}${unwind(onThrow)}',
      Yield(value: final element, :final onResume, :final onCancel) =>
        '  yield ${value(element)} resume ${edge(onResume)}${onCancel == null ? '' : ' cancel ${edge(onCancel)}'}',
      YieldStream(
        :final stream,
        :final onResume,
        :final onCancel,
        :final onThrow,
      ) =>
        '  yield* ${value(stream)} resume ${edge(onResume)} cancel ${edge(onCancel)}${unwind(onThrow)}',
      Throw(
        isRecorded: true,
        :final exception,
        stackTrace: final trace,
        :final onThrow,
      ) =>
        '  throw.recorded ${value(exception)}${trace == null ? '' : ', ${value(trace)}'}${unwind(onThrow)}',
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
