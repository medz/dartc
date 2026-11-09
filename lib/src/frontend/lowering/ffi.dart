import 'dart:ffi' as ffi;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';

final _library = Uri.parse('dart:ffi');

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
  return null;
}

Type nativeType(dart.DartType type) {
  if (type is dart.InterfaceType && type.nullabilitySuffix == .none) {
    final library = type.element.library;
    if (library.uri == _library) {
      for (final MapEntry(:key, :value) in FfiTypes.scalarTypes.entries) {
        if (type.element == library.getClass(value.name)) return key;
      }
      if (type.element == library.getClass('Void')) return ffi.Void;
      if (type.element == library.getClass('Pointer')) {
        final element = nativeType(type.typeArguments.single);
        if (element.pointerType case final pointer?) return pointer;
      }
    }
  }
  throw UnsupportedError('Native signature type: $type');
}

Value? lowerFfi(
  ExecutableElement member,
  List<Value> operands,
  Value Function(Instruction) emit, {
  ValueType? result,
}) {
  final library = member.library;
  if (library.uri != _library) return null;
  member = member.baseElement;
  final pointer = library.getClass('Pointer')!;
  if (member == pointer.getNamedConstructor('fromAddress') &&
      result is ClassType &&
      FfiTypes.pointerElement(result) != null) {
    return emit(PointerFromAddress(operands.single, result));
  }
  if (member == pointer.getGetter('address') &&
      FfiTypes.pointerElement(operands.single.type) != null) {
    return emit(PointerAddress(operands.single));
  }
  for (final type in FfiTypes.scalarTypes.values) {
    final access = library.getExtension('${type.name}Pointer')!;
    if (member == access.getGetter('value')) {
      return emit(LoadNative(operands.single));
    }
    if (member == access.getSetter('value')) {
      return emit(StoreNative(operands[0], operands[1]));
    }
    if (member == access.getMethod('+') ||
        member == access.getMethod('elementAt')) {
      return emit(PointerOffset(operands[0], operands[1]));
    }
    if (member == access.getMethod('-')) {
      final index = emit(
        IntBinary(.subtract, const Constant.integer(0), operands[1]),
      );
      return emit(PointerOffset(operands[0], index));
    }
    if (member == access.getMethod('[]')) {
      final pointer = emit(PointerOffset(operands[0], operands[1]));
      return emit(LoadNative(pointer));
    }
    if (member == access.getMethod('[]=')) {
      final pointer = emit(PointerOffset(operands[0], operands[1]));
      return emit(StoreNative(pointer, operands[2]));
    }
  }
  return null;
}
