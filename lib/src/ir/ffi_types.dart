import 'dart:ffi' as ffi;

import 'type.dart';

/// Canonical Dart FFI declaration identities, independent of pointer layout.
abstract final class FfiTypes() {
  static final _library = Uri.parse('dart:ffi');

  /// The bound of native type arguments.
  static final nativeType = ClassType(_library, 'NativeType', isAbstract: true);

  /// Native types with a storage size.
  static final sizedNativeType = ClassType(
    _library,
    'SizedNativeType',
    superclass: nativeType,
    isAbstract: true,
  );

  /// Canonical declarations of the fixed-width native integer types.
  static final Map<Type, ClassType> integerTypes = .unmodifiable({
    for (final MapEntry(:key, :value) in _integers.entries)
      key: ClassType(_library, value.$1, superclass: sizedNativeType),
  });

  /// The native signed 64-bit type, distinct from Dart `int`.
  static final int64 = integerTypes[ffi.Int64]!;

  /// The Dart pointer declaration; its type argument describes native storage.
  static final pointer = ClassType(
    _library,
    'Pointer',
    interfaces: [sizedNativeType],
    typeParameters: [
      TypeParameterType('T')
        ..initializeBound(nativeType)
        ..initializeDefaultType(nativeType),
    ],
  );

  /// Supported FFI pointer type values and their canonical Dart types.
  static final Map<Type, ClassType> pointerTypes = .unmodifiable({
    for (final MapEntry(:key, :value) in _integers.entries)
      value.$2: pointer.instantiate([integerTypes[key]!]),
  });

  /// A pointer to native signed 64-bit storage.
  static final int64Pointer = pointerTypes[ffi.Pointer<ffi.Int64>]!;

  /// The native integer element of [type], or null for another Dart type.
  static Type? pointerElement(ValueType type) {
    if (type is ClassType && type.declaration == pointer) {
      for (final MapEntry(:key, :value) in integerTypes.entries) {
        if (type.typeArguments.single == value) return key;
      }
    }
    return null;
  }

  /// The Dart value type corresponding to a supported native signature type.
  static ValueType valueType(Type native) {
    if (native == ffi.Void) return .voidType;
    if (integerTypes.containsKey(native)) return .integer;
    if (native == ffi.Double) return .floating;
    if (pointerTypes[native] case final pointer?) return pointer;
    throw UnsupportedError('Native value type: $native');
  }
}

const _integers = {
  ffi.Int8: ('Int8', ffi.Pointer<ffi.Int8>),
  ffi.Uint8: ('Uint8', ffi.Pointer<ffi.Uint8>),
  ffi.Int16: ('Int16', ffi.Pointer<ffi.Int16>),
  ffi.Uint16: ('Uint16', ffi.Pointer<ffi.Uint16>),
  ffi.Int32: ('Int32', ffi.Pointer<ffi.Int32>),
  ffi.Uint32: ('Uint32', ffi.Pointer<ffi.Uint32>),
  ffi.Int64: ('Int64', ffi.Pointer<ffi.Int64>),
  ffi.Uint64: ('Uint64', ffi.Pointer<ffi.Uint64>),
};
