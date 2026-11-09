import 'dart:ffi';

import 'native_type.dart';

/// An explicit FFI signature whose parameters and result retain native types.
///
/// The unnamed constructor accepts supported `dart:ffi` type literals. Use
/// [NativeSignature.types] for nested pointers and native function signatures.
/// Unsized parameters and results other than [Void] throw [UnsupportedError].
final class NativeSignature.types(
  final NativeTypeRef result,
  Iterable<NativeTypeRef> parameters,
) {
  /// Parameter types in declaration order.
  final List<NativeTypeRef> parameters = .unmodifiable(parameters);

  new(Type result, Iterable<Type> parameters)
    : this.types(NativeTypeRef.of(result), parameters.map(NativeTypeRef.of));

  this {
    for (final type in [if (!result.isVoid) result, ...this.parameters]) {
      type.nativeSize;
    }
  }

  /// Formats a C function declarator, including nested pointer types.
  String declaration(String name) => result.declaration(
    '$name(${parameters.isEmpty ? 'void' : parameters.map((p) => p.declaration('')).join(', ')})',
  );

  @override
  bool operator ==(Object other) =>
      other is NativeSignature &&
      result == other.result &&
      parameters.length == other.parameters.length &&
      parameters.indexed.every((p) => p.$2 == other.parameters[p.$1]);

  @override
  int get hashCode => Object.hash(result, Object.hashAll(parameters));
}

/// A native type described by FFI declarations rather than host reflection.
///
/// Scalars retain their `dart:ffi` [Type]. Pointer and function nodes preserve
/// types that cannot be constructed as host [Type] values from source metadata.
sealed class const NativeTypeRef() {
  /// Describes a supported scalar or scalar-pointer type literal.
  factory of(Type type) {
    if (type.pointerElement case final element?) {
      return NativePointerType(NativeScalarType(element));
    }
    return NativeScalarType(type);
  }

  /// Whether this is the native void marker.
  bool get isVoid => switch (this) {
    NativeScalarType(:final type) => type == Void,
    _ => false,
  };

  /// Whether this value uses a native floating-point register.
  bool get isFloating => switch (this) {
    NativeScalarType(:final type) => type.isFloating,
    _ => false,
  };

  /// Whether this is the native single-precision scalar.
  bool get isSinglePrecision => switch (this) {
    NativeScalarType(:final type) => type == Float,
    _ => false,
  };

  /// Integer width and signedness, or null for another native type.
  ({int bytes, bool signed, Type pointer})? get integerLayout => switch (this) {
    NativeScalarType(:final type) => type.integerLayout,
    _ => null,
  };

  /// Storage size on the toolchain's supported 64-bit native targets.
  ///
  /// Void and function markers have no storage size.
  int get nativeSize => switch (this) {
    NativeScalarType(:final type) => type.nativeSize,
    NativePointerType() => 8,
    NativeFunctionType() => throw UnsupportedError(
      'Native functions are unsized.',
    ),
  };

  /// Formats a C declarator with [name], or an unnamed type when it is empty.
  String declaration(String name) => switch (this) {
    NativeScalarType(:final type) =>
      '${type.cType}${name.isEmpty || name.startsWith('*') ? '' : ' '}$name',
    NativePointerType(element: final NativeFunctionType function) =>
      function.declaration('(*$name)'),
    NativePointerType(:final element) => element.declaration(
      '*${name.isEmpty ? '' : ' '}$name',
    ),
    NativeFunctionType(:final signature) => signature.declaration(name),
  };

  @override
  String toString() => declaration('');
}

/// A fixed-width native scalar or the `dart:ffi` void marker.
final class NativeScalarType(final Type type) extends NativeTypeRef {
  this {
    if (type != Void && !type.isFloating && type.integerLayout == null) {
      throw UnsupportedError('Native scalar type: $type');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NativeScalarType && type == other.type;

  @override
  int get hashCode => type.hashCode;
}

/// A `dart:ffi` pointer retaining its complete native element type.
final class NativePointerType(final NativeTypeRef element)
    extends NativeTypeRef {
  @override
  bool operator ==(Object other) =>
      other is NativePointerType && element == other.element;

  @override
  int get hashCode => Object.hash(NativePointerType, element);
}

/// The unsized `dart:ffi` native function marker and its complete signature.
final class NativeFunctionType(final NativeSignature signature)
    extends NativeTypeRef {
  @override
  bool operator ==(Object other) =>
      other is NativeFunctionType && signature == other.signature;

  @override
  int get hashCode => Object.hash(NativeFunctionType, signature);
}
