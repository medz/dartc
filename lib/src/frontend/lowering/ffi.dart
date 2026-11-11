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
  if (element == library.getClass('NativeType')) return FfiTypes.nativeType;
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

NativeTypeRef nativeType(dart.DartType type) {
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

NativeSignature nativeSignature(dart.FunctionType type) {
  if (type.nullabilitySuffix != .none ||
      type.typeParameters.isNotEmpty ||
      type.formalParameters.any((p) => !p.isRequiredPositional)) {
    throw UnsupportedError(
      'Expected a non-generic positional FFI function signature.',
    );
  }
  return NativeSignature.types(
    nativeType(type.returnType),
    type.formalParameters.map((p) => nativeType(p.type)),
  );
}

Value? lowerFfi(
  ExecutableElement member,
  List<Value> operands,
  Value Function(Instruction) emit, {
  ValueType? result,
}) {
  final library = member.library;
  if (library.uri != _library) return null;
  Value scalar(Value value, ValueType type) =>
      value.type == type ? value : emit(TypeView(value, type));
  member = member.baseElement;
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
