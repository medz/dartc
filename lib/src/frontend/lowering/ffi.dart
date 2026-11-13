import 'dart:ffi' as ffi;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

final _library = Uri.parse('dart:ffi');

bool isAsFunction(ExecutableElement member) =>
    member.library.uri == _library &&
    member.baseElement ==
        member.library
            .getExtension('NativeFunctionPointer')
            ?.getMethod('asFunction');

bool isPointerCast(ExecutableElement member) =>
    member.library.uri == _library &&
    member.baseElement == member.library.getClass('Pointer')?.getMethod('cast');

ClassType? ffiClass(InterfaceElement element) {
  final library = element.library;
  if (library.uri != _library) return null;
  if (element == library.getClass('Finalizable')) return FfiTypes.finalizable;
  if (element == library.getClass('NativeType')) return FfiTypes.nativeType;
  if (element == library.getClass('AbiSpecificInteger')) {
    return FfiTypes.abiSpecificInteger;
  }
  if (element == library.getClass('SizedNativeType')) {
    return FfiTypes.sizedNativeType;
  }
  for (final type in FfiTypes.scalarTypes.values) {
    if (element == library.getClass(type.name)) return type;
  }
  if (element == library.getClass('Pointer')) return FfiTypes.pointer;
  if (element == library.getClass('Void')) return FfiTypes.voidType;
  if (element == library.getClass('NativeFunction')) {
    return FfiTypes.nativeFunction;
  }
  return null;
}

NativeTypeRef nativeType(
  dart.DartType type, {
  ValueType Function(dart.DartType)? bind,
}) {
  if (bind != null) return FfiTypes.describe(bind(type));
  if (type is dart.InterfaceType && type.nullabilitySuffix == .none) {
    final library = type.element.library;
    if (library.uri == _library) {
      for (final MapEntry(:key, :value) in FfiTypes.scalarTypes.entries) {
        if (type.element == library.getClass(value.name)) {
          return NativeScalarType(key);
        }
      }
      if (type.element == library.getClass('Void')) {
        return NativeScalarType(ffi.Void);
      }
      if (type.element == library.getClass('Pointer')) {
        return NativePointerType(nativeType(type.typeArguments.single));
      }
      if (type.element == library.getClass('NativeFunction')) {
        final signature = type.typeArguments.single;
        if (signature is dart.FunctionType) {
          return NativeFunctionType(nativeSignature(signature));
        }
      }
    }
  }
  throw UnsupportedError('Native signature type: $type');
}

NativeSignature nativeSignature(
  dart.FunctionType type, {
  ValueType Function(dart.DartType)? bind,
}) {
  if (type.nullabilitySuffix != .none ||
      type.typeParameters.isNotEmpty ||
      type.formalParameters.any((p) => !p.isRequiredPositional)) {
    throw UnsupportedError(
      'Expected a non-generic positional FFI function signature.',
    );
  }
  return NativeSignature.types(
    nativeType(type.returnType, bind: bind),
    type.formalParameters.map((p) => nativeType(p.type, bind: bind)),
  );
}

Value? lowerFfi(
  ExecutableElement member,
  List<Value> operands,
  Value Function(Instruction) emit, {
  ValueType? result,
  FunctionTarget Function(ExecutableElement)? bind,
  Map<String, Value> named = const {},
}) {
  final library = member.library;
  if (library.uri != _library) return null;
  Value scalar(Value value, ValueType type) =>
      value.type == type ? value : emit(TypeView(value, type));
  member = member.baseElement;
  LibraryElement typedData() => library.fragments
      .expand((fragment) => fragment.importedLibraries)
      .firstWhere((library) => library.uri == Uri.parse('dart:typed_data'));
  Value typedView(
    Value owner,
    Value address,
    Value length,
    Value bytes,
    ClassType type,
  ) {
    final buffer = emit(
      DirectCall(bind!(typedData().getTopLevelFunction('_nativeBuffer')!), [
        owner,
        address,
        length,
        bytes,
      ]),
    );
    return emit(
      InstanceCall(
        bind(typedData().getClass('ByteBuffer')!.getMethod('as${type.name}')!),
        buffer,
        [const Constant.integer(0), length],
      ),
    );
  }

  if (bind != null &&
      result is ClassType &&
      (member == library.getClass('Struct')?.getMethod('create') ||
          member == library.getClass('Union')?.getMethod('create'))) {
    if (operands.isEmpty || operands.first == const Constant.nullValue()) {
      return emit(NativeView(result));
    }
    final owner = emit(
      DirectCall(bind(typedData().getTopLevelFunction('_nativeStorage')!), [
        operands.first,
        operands.length > 1 ? operands[1] : const Constant.integer(0),
        emit(NativeSize(result.nativeType!)),
      ]),
    );
    return emit(
      NativeView(
        result,
        owner: owner,
        address: emit(
          DirectCall(bind(typedData().getTopLevelFunction('_nativeAddress')!), [
            owner,
          ]),
        ),
      ),
    );
  }
  final pointer = library.getClass('Pointer')!;
  if (isPointerCast(member) && result is ClassType) {
    return emit(
      PointerFromAddress(emit(PointerAddress(operands.single)), result),
    );
  }
  if (member == pointer.getNamedConstructor('fromAddress') &&
      result is ClassType &&
      FfiTypes.isPointer(result)) {
    return emit(PointerFromAddress(scalar(operands.single, .integer), result));
  }
  if (member == pointer.getGetter('address') &&
      FfiTypes.isPointer(operands.single.type)) {
    return emit(PointerAddress(operands.single));
  }
  if (member == pointer.getGetter('hashCode') &&
      FfiTypes.isPointer(operands.single.type)) {
    return emit(ObjectHashCode(operands.single));
  }
  final access = member.enclosingElement;
  if (access is! ExtensionElement) return null;
  final array = library.getClass('Array');
  if (bind != null &&
      member == access.getGetter('elements') &&
      access.extendedType is dart.InterfaceType &&
      (access.extendedType as dart.InterfaceType).element == array &&
      result is ClassType &&
      result.library == Uri.parse('dart:typed_data')) {
    final receiver = operands.single;
    final length = emit(
      DirectCall(bind(library.getTopLevelFunction('_arrayLength')!), [
        receiver,
      ]),
    );
    final address = emit(
      DirectCall(bind(library.getTopLevelFunction('_arrayAddress')!), [
        receiver,
        const Constant.integer(0),
      ]),
    );
    final bytes = emit(
      NativeSize(
        FfiTypes.describe((receiver.type as ClassType).typeArguments.single),
      ),
    );
    return typedView(receiver, address, length, bytes, result);
  }
  if (access.extendedType is dart.InterfaceType &&
      (access.extendedType as dart.InterfaceType).element == array &&
      bind != null &&
      (member.name == '[]' || member.name == '[]=')) {
    final receiver = operands.first;
    final element = (receiver.type as ClassType).typeArguments.single;
    if (access == library.getExtension('ArrayArray')) {
      final callee = bind(
        library.getTopLevelFunction(
          member.name == '[]' ? '_arraySlice' : '_arrayStore',
        )!,
      );
      return emit(
        DirectCall(
          callee,
          operands,
          typeArguments: [(element as ClassType).typeArguments.single],
        ),
      );
    }
    final address = emit(
      DirectCall(
        bind(library.getTopLevelFunction('_arrayAddress')!),
        operands.take(2),
      ),
    );
    final storage = FfiTypes.describe(element);
    final value = member.name == '[]'
        ? _load(
            address,
            storage,
            FfiTypes.dartValueType(element),
            receiver,
            emit,
          )
        : _store(address, storage, operands.last, emit);
    emit(KeepAlive(receiver));
    return value;
  }
  if (access == library.getExtension('StructPointer') ||
      access == library.getExtension('UnionPointer')) {
    final pointerType = operands.first.type as ClassType;
    final viewType = pointerType.typeArguments.single as ClassType;
    final address = emit(PointerAddress(operands.first));
    Value offset(Value index) => emit(
      IntBinary(
        .add,
        address,
        emit(
          IntBinary(.multiply, index, emit(NativeSize(viewType.nativeType!))),
        ),
      ),
    );
    if (member == access.getGetter('ref') || member == access.getMethod('[]')) {
      return emit(
        NativeView(
          viewType,
          address: operands.length == 1 ? address : offset(operands[1]),
          owner: operands.first,
        ),
      );
    }
    if (member == access.getSetter('ref') ||
        member == access.getMethod('[]=')) {
      final result = emit(
        CopyNative(
          operands.length == 2 ? address : offset(operands[1]),
          emit(NativeAddress(operands.last)),
          viewType.nativeType!,
        ),
      );
      emit(KeepAlive(operands.last));
      return result;
    }
    if (member == access.getMethod('+') ||
        member == access.getMethod('elementAt') ||
        member == access.getMethod('-')) {
      final index = member.name == '-'
          ? emit(IntBinary(.subtract, const Constant.integer(0), operands[1]))
          : operands[1];
      return emit(PointerFromAddress(offset(index), pointerType));
    }
  }
  final pointerElements = access == library.getExtension('PointerPointer');
  NativeScalarType? storage;
  if (pointerElements) {
    storage = NativeScalarType(ffi.Uint64);
  } else {
    for (final MapEntry(key: native, value: type)
        in FfiTypes.scalarTypes.entries) {
      if (access == library.getExtension('${type.name}Pointer')) {
        storage = NativeScalarType(native);
        break;
      }
    }
  }
  if (storage == null) return null;
  if (bind != null &&
      member == access.getMethod('asTypedList') &&
      result is ClassType &&
      result.library == Uri.parse('dart:typed_data')) {
    final view = typedView(
      operands.first,
      emit(PointerAddress(operands.first)),
      operands[1],
      Constant.integer(storage.nativeSize),
      result,
    );
    if (named['finalizer'] case final callback?) {
      emit(
        DirectCall(
          bind(library.getTopLevelFunction('_attachPointerFinalizer')!),
          [
            callback,
            emit(
              DirectCall(
                bind(typedData().getTopLevelFunction('_nativeOwner')!),
                [view],
              ),
            ),
            operands.first,
            named['token'] ?? const Constant.nullValue(),
            emit(
              IntBinary(
                .multiply,
                operands[1],
                Constant.integer(storage.nativeSize),
              ),
            ),
          ],
        ),
      );
    }
    return view;
  }
  final nativeStorage = storage;
  Value load(Value address) {
    final value = emit(LoadNative(address, nativeStorage));
    return pointerElements
        ? emit(
            PointerFromAddress(
              value,
              (operands.first.type as ClassType).typeArguments.single
                  as ClassType,
            ),
          )
        : value;
  }

  Value store(Value address, Value value) => emit(
    StoreNative(
      address,
      nativeStorage,
      pointerElements
          ? emit(PointerAddress(value))
          : scalar(value, FfiTypes.valueType(nativeStorage)),
    ),
  );

  if (member == access.getGetter('value')) {
    return load(emit(PointerAddress(operands.single)));
  }
  if (member == access.getSetter('value')) {
    return store(emit(PointerAddress(operands[0])), operands[1]);
  }
  if (member == access.getMethod('+') ||
      member == access.getMethod('elementAt')) {
    return emit(PointerOffset(operands[0], scalar(operands[1], .integer)));
  }
  if (member == access.getMethod('-')) {
    final index = emit(
      IntBinary(
        .subtract,
        const Constant.integer(0),
        scalar(operands[1], .integer),
      ),
    );
    return emit(PointerOffset(operands[0], index));
  }
  final read = member == access.getMethod('[]');
  if (read || member == access.getMethod('[]=')) {
    final offset = emit(
      IntBinary(
        .multiply,
        scalar(operands[1], .integer),
        Constant.integer(storage.nativeSize),
      ),
    );
    final address = emit(
      IntBinary(.add, emit(PointerAddress(operands[0])), offset),
    );
    return read ? load(address) : store(address, operands[2]);
  }
  return null;
}

IrFunction nativeVariableBody(
  FunctionTarget target,
  NativeReference reference,
) {
  final block = Block(target.parameterTypes);
  final address = block.emit(NativeSymbolAddress(reference));
  final value = target.parameterTypes.isEmpty
      ? _load(
          address,
          reference.type,
          target.returnType,
          const Constant.nullValue(),
          block.emit,
        )
      : _store(address, reference.type, block.parameters.single, block.emit);
  block.finish(target.parameterTypes.isEmpty ? Return(value) : const Return());
  return IrFunction(target, [block]);
}

Value? Function(FunctionTarget, Block)? nativeFieldBody(
  ExecutableElement element,
  ClassType? owner,
  FunctionTarget Function(ExecutableElement) bind,
) {
  if (element is! PropertyAccessorElement ||
      owner?.nativeType is! NativeCompoundType) {
    return null;
  }
  final native = owner!.nativeType as NativeCompoundType;
  final field = element.variable as FieldElement;
  final fields = (field.enclosingElement as InterfaceElement).fields
      .where((field) => !field.isStatic && !field.isOriginGetterSetter)
      .toList();
  final index = fields.indexOf(field);
  if (index < 0) return null;
  final storage = native.fields[index].type;
  FunctionTarget? arrayConstructor, copyArray;
  if (storage is NativeArrayType) {
    final library = (field.type as dart.InterfaceType).element.library;
    arrayConstructor = bind(
      library.getClass('Array')!.getNamedConstructor('_view')!,
    );
    if (element is SetterElement) {
      copyArray = bind(library.getTopLevelFunction('_copyArray')!);
    }
  }
  return (target, block) {
    final receiver = block.parameters.first;
    final address = block.emit(
      IntBinary(
        .add,
        block.emit(NativeAddress(receiver)),
        block.emit(NativeFieldOffset(native, index)),
      ),
    );
    if (storage is NativeArrayType) {
      Value arrayView(ClassType type) {
        final dimensions = <Constant>[];
        NativeTypeRef dimension = storage;
        while (dimension is NativeArrayType) {
          dimensions.add(Constant.integer(dimension.length));
          dimension = dimension.element;
        }
        return block.emit(
          Construct(arrayConstructor!, [
            receiver,
            address,
            SequenceConstant(CoreTypes.listOf(.integer), dimensions),
            block.emit(NativeSize(storage.element)),
          ], instantiatedType: type),
        );
      }

      if (element is GetterElement) {
        return arrayView(target.returnType as ClassType);
      }
      final value = block.parameters.last;
      final view = arrayView(value.type as ClassType);
      return block.emit(DirectCall(copyArray!, [view, value]));
    }
    final result = element is GetterElement
        ? _load(address, storage, target.returnType, receiver, block.emit)
        : _store(address, storage, block.parameters.last, block.emit);
    block.emit(KeepAlive(receiver));
    return result;
  };
}

Value _load(
  Value address,
  NativeTypeRef storage,
  ValueType type,
  Value owner,
  Value Function(Instruction) emit,
) => switch (storage) {
  NativeScalarType() => emit(LoadNative(address, storage)),
  NativePointerType() => emit(
    PointerFromAddress(
      emit(LoadNative(address, NativeScalarType(ffi.Uint64))),
      type as ClassType,
    ),
  ),
  NativeCompoundType() => emit(
    NativeView(type as ClassType, address: address, owner: owner),
  ),
  _ => throw UnsupportedError('Native element storage: $storage'),
};

Value _store(
  Value address,
  NativeTypeRef storage,
  Value value,
  Value Function(Instruction) emit,
) {
  final result = switch (storage) {
    NativeScalarType() => emit(StoreNative(address, storage, value)),
    NativePointerType() => emit(
      StoreNative(
        address,
        NativeScalarType(ffi.Uint64),
        emit(PointerAddress(value)),
      ),
    ),
    NativeCompoundType() => emit(
      CopyNative(address, emit(NativeAddress(value)), storage),
    ),
    _ => throw UnsupportedError('Native element storage: $storage'),
  };
  emit(KeepAlive(value));
  return result;
}
