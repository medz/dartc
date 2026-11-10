import 'dart:ffi' as ffi;

import 'package:dartc/interop.dart';

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

  /// Canonical declarations of the supported native scalar types.
  static final Map<Type, ClassType> scalarTypes = .unmodifiable({
    for (final MapEntry(:key, :value) in _scalars.entries)
      key: ClassType(_library, value.$1, superclass: sizedNativeType),
  });

  /// The native signed 64-bit type, distinct from Dart `int`.
  static final int64 = scalarTypes[ffi.Int64]!;

  /// The unsized native void declaration, distinct from Dart `void`.
  static final voidType = ClassType(
    _library,
    'Void',
    interfaces: [nativeType],
    isAbstract: true,
  );

  /// The unsized native function marker, parameterized by its FFI signature.
  static final nativeFunction = ClassType(
    _library,
    'NativeFunction',
    interfaces: [nativeType],
    isAbstract: true,
    typeParameters: [
      TypeParameterType('T')
        ..initializeBound(.function)
        ..initializeDefaultType(.function),
    ],
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

  /// The reified pointer type; element types describe native storage statically.
  static final pointerRuntimeType = pointer.instantiate([ValueType.never]);

  /// Supported FFI pointer type values and their canonical Dart types.
  static final Map<Type, ClassType> pointerTypes = .unmodifiable({
    for (final MapEntry(:key, :value) in _scalars.entries)
      value.$2: pointer.instantiate([scalarTypes[key]!]),
    ffi.Pointer<ffi.Void>: pointer.instantiate([voidType]),
  });

  /// A pointer to native signed 64-bit storage.
  static final int64Pointer = pointerTypes[ffi.Pointer<ffi.Int64>]!;

  /// Whether [type] is a non-nullable instance of the Dart FFI pointer declaration.
  static bool isPointer(ValueType type) =>
      type is ClassType && type.declaration == pointer;

  /// Resolves a native type description to its canonical Dart declaration.
  static ClassType resolve(NativeTypeRef type) => switch (type) {
    NativeScalarType(:final type) =>
      type == ffi.Void ? voidType : scalarTypes[type]!,
    NativePointerType(:final element) => pointer.instantiate([
      resolve(element),
    ]),
    NativeFunctionType(:final signature) => nativeFunction.instantiate([
      FunctionType(
        resolve(signature.result),
        signature.parameters.map(resolve),
      ),
    ]),
  };

  /// Describes an already-bound supported native declaration without host reflection.
  static NativeTypeRef describe(ValueType type) {
    if (type == voidType) return NativeScalarType(ffi.Void);
    for (final MapEntry(:key, :value) in scalarTypes.entries) {
      if (type == value) return NativeScalarType(key);
    }
    if (isPointer(type)) {
      return NativePointerType(
        describe((type as ClassType).typeArguments.single),
      );
    }
    if (type is ClassType && type.declaration == nativeFunction) {
      final signature = type.typeArguments.single;
      if (signature is FunctionType &&
          signature.typeParameters.isEmpty &&
          signature.optionalPositional == 0 &&
          signature.named.isEmpty) {
        return NativeFunctionType(
          NativeSignature.types(
            describe(signature.result),
            signature.parameters.map(describe),
          ),
        );
      }
    }
    throw UnsupportedError('Native declaration: ${type.dartName}');
  }

  /// The native scalar element of [type], or null for another Dart type.
  static Type? pointerElement(ValueType type) {
    if (type is ClassType && type.declaration == pointer) {
      for (final MapEntry(:key, :value) in scalarTypes.entries) {
        if (type.typeArguments.single == value) return key;
      }
    }
    return null;
  }

  /// The Dart value type corresponding to a supported native signature type.
  static ValueType valueType(NativeTypeRef native) => switch (native) {
    NativeScalarType() when native.isVoid => .voidType,
    NativeScalarType() when native.isFloating => .floating,
    NativeScalarType() => .integer,
    NativePointerType() => resolve(native),
    NativeFunctionType() => throw UnsupportedError(
      'A native function requires a pointer.',
    ),
  };

  /// Whether a Dart function can call [native], including pointer variance.
  static bool canCall(NativeSignature native, FunctionType dart) {
    if (dart.typeParameters.isNotEmpty ||
        dart.freeTypeParameters.isNotEmpty ||
        dart.optionalPositional != 0 ||
        dart.named.isNotEmpty ||
        dart.parameters.length != native.parameters.length) {
      return false;
    }
    bool matches(NativeTypeRef type, ValueType value, {bool result = false}) {
      final expected = valueType(type);
      return type is NativePointerType
          ? isPointer(value) &&
                (result ? value.accepts(expected) : expected.accepts(value))
          : value == expected;
    }

    return matches(native.result, dart.result, result: true) &&
        native.parameters.indexed.every(
          (p) => matches(p.$2, dart.parameters[p.$1]),
        );
  }
}

const _scalars = {
  ffi.Int8: ('Int8', ffi.Pointer<ffi.Int8>),
  ffi.Uint8: ('Uint8', ffi.Pointer<ffi.Uint8>),
  ffi.Int16: ('Int16', ffi.Pointer<ffi.Int16>),
  ffi.Uint16: ('Uint16', ffi.Pointer<ffi.Uint16>),
  ffi.Int32: ('Int32', ffi.Pointer<ffi.Int32>),
  ffi.Uint32: ('Uint32', ffi.Pointer<ffi.Uint32>),
  ffi.Int64: ('Int64', ffi.Pointer<ffi.Int64>),
  ffi.Uint64: ('Uint64', ffi.Pointer<ffi.Uint64>),
  ffi.Float: ('Float', ffi.Pointer<ffi.Float>),
  ffi.Double: ('Double', ffi.Pointer<ffi.Double>),
};
