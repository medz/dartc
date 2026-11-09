import 'dart:ffi' as ffi;

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart' as dart;
import 'package:dartc/ir.dart';

final _library = Uri.parse('dart:ffi');

ClassType? ffiClass(InterfaceElement element) {
  final library = element.library;
  if (library.uri != _library) return null;
  if (element == library.getClass('NativeType')) return FfiTypes.nativeType;
  if (element == library.getClass('SizedNativeType')) {
    return FfiTypes.sizedNativeType;
  }
  if (element == library.getClass('Int64')) return FfiTypes.int64;
  if (element == library.getClass('Pointer')) return FfiTypes.pointer;
  return null;
}

Type nativeType(dart.DartType type) {
  if (type is dart.InterfaceType && type.nullabilitySuffix == .none) {
    final library = type.element.library;
    if (library.uri == _library) {
      if (type.element == library.getClass('Int64')) return ffi.Int64;
      if (type.element == library.getClass('Double')) return ffi.Double;
      if (type.element == library.getClass('Void')) return ffi.Void;
      if (type.element == library.getClass('Pointer') &&
          nativeType(type.typeArguments.single) == ffi.Int64) {
        return ffi.Pointer<ffi.Int64>;
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
      result == FfiTypes.int64Pointer) {
    return PointerFromAddress(operands.single);
  }
  if (member == pointer.getGetter('address') &&
      operands.single.type == FfiTypes.int64Pointer) {
    return PointerAddress(operands.single);
  }
  final access = library.getExtension('Int64Pointer')!;
  if (member == access.getGetter('value')) {
    return LoadNativeInt64(operands.single);
  }
  if (member == access.getSetter('value')) {
    return StoreNativeInt64(operands[0], operands[1]);
  }
  return null;
}
