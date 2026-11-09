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

Instruction? ffiOperation(
  ExecutableElement member,
  List<Value> operands, {
  ValueType? result,
}) {
  final library = member.library;
  if (library.uri != _library) return null;
  member = member.baseElement;
  final pointer = library.getClass('Pointer')!;
  if (member == pointer.getNamedConstructor('fromAddress') &&
      result is ClassType &&
      FfiTypes.pointerElement(result) != null) {
    return PointerFromAddress(operands.single, result);
  }
  if (member == pointer.getGetter('address') &&
      FfiTypes.pointerElement(operands.single.type) != null) {
    return PointerAddress(operands.single);
  }
  for (final type in FfiTypes.scalarTypes.values) {
    final access = library.getExtension('${type.name}Pointer')!;
    if (member == access.getGetter('value')) {
      return LoadNative(operands.single);
    }
    if (member == access.getSetter('value')) {
      return StoreNative(operands[0], operands[1]);
    }
  }
  return null;
}
