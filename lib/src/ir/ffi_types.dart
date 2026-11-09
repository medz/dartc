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

  /// The native signed 64-bit type, distinct from Dart `int`.
  static final int64 = ClassType(
    _library,
    'Int64',
    superclass: sizedNativeType,
  );

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

  /// A pointer to native signed 64-bit storage.
  static final int64Pointer = pointer.instantiate([int64]);

  /// The Dart value type corresponding to a supported native signature type.
  static ValueType valueType(Type native) {
    if (native == ffi.Void) return .voidType;
    if (native == ffi.Int64) return .integer;
    if (native == ffi.Pointer<ffi.Int64>) return int64Pointer;
    throw UnsupportedError('Native value type: $native');
  }
}
