import 'dart:ffi';

import 'native_type.dart';

/// An explicit FFI signature whose parameters and result retain native types.
///
/// The unnamed constructor accepts supported `dart:ffi` type literals. Use
/// [NativeSignature.types] for nested pointers and native function signatures.
/// Unsized parameters and results other than [Void] throw [UnsupportedError].
/// Variadic arguments must already use C's promoted types (`Int` or wider, and
/// `Double`); narrow integers, `Bool` and `Float` are rejected, not converted.
final class NativeSignature.types(
  final NativeTypeRef result,
  Iterable<NativeTypeRef> parameters, {

  /// Index of the first variadic argument, or null for a fixed signature.
  ///
  /// May equal the parameter count when no variadic arguments are passed.
  final int? variadicStart,
}) {
  /// Parameter types in declaration order.
  final List<NativeTypeRef> parameters = .unmodifiable(parameters);

  new(Type result, Iterable<Type> parameters, {int? variadicStart})
    : this.types(
        NativeTypeRef.of(result),
        parameters.map(NativeTypeRef.of),
        variadicStart: variadicStart,
      );

  this {
    if (variadicStart case final start?) {
      RangeError.checkValueInInterval(
        start,
        0,
        this.parameters.length,
        'variadicStart',
      );
      for (final type in this.parameters.skip(start)) {
        if (type.isSinglePrecision ||
            type.isBoolean ||
            (type.integerLayout?.bytes ?? 4) < 4) {
          throw UnsupportedError(
            'Variadic arguments require promoted native types: use Int or Double instead of $type.',
          );
        }
      }
    }
    for (final type in [if (!result.isVoid) result, ...this.parameters]) {
      if (!type.isSized || type is NativeArrayType) {
        throw UnsupportedError('Unsized or array native parameter: $type');
      }
    }
  }

  /// Resolves ABI-dependent scalar storage while retaining the variadic boundary.
  NativeSignature resolveAbi(Abi abi) => .types(
    result.resolveAbi(abi),
    parameters.map((type) => type.resolveAbi(abi)),
    variadicStart: variadicStart,
  );

  /// Formats a C function declarator, including nested pointer types.
  ///
  /// [abi] is required when a declaration contains an ABI-specific integer.
  /// [typeNames] supplies C tags without changing native declaration identities.
  String declaration(
    String name, {
    Abi? abi,
    Map<NativeTypeRef, String> typeNames = const {},
  }) {
    final arguments = [
      if (parameters.isEmpty && variadicStart == null) 'void',
      ...parameters
          .take(variadicStart ?? parameters.length)
          .map((p) => p.declaration('', abi: abi, typeNames: typeNames)),
      if (variadicStart != null) '...',
    ];
    return result.declaration(
      '$name(${arguments.join(', ')})',
      abi: abi,
      typeNames: typeNames,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NativeSignature &&
      result == other.result &&
      variadicStart == other.variadicStart &&
      parameters.length == other.parameters.length &&
      parameters.indexed.every((p) => p.$2 == other.parameters[p.$1]);

  @override
  int get hashCode =>
      Object.hash(result, Object.hashAll(parameters), variadicStart);
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

  /// Selects an ABI-specific integer's storage, leaving other types unchanged.
  NativeTypeRef resolveAbi(Abi abi) => switch (this) {
    NativeAbiIntegerType(:final mapping) =>
      mapping[abi] ?? (throw UnsupportedError('No $abi mapping for $this.')),
    _ => this,
  };

  /// Whether this is scalar storage, including an unresolved ABI integer.
  bool get isScalar => this is NativeScalarType || this is NativeAbiIntegerType;

  /// Whether this is the native void marker.
  bool get isVoid => switch (this) {
    NativeScalarType(:final type) => type == Void,
    _ => false,
  };

  /// Whether this is the native boolean scalar, whose Dart value is `bool`.
  bool get isBoolean =>
      this is NativeScalarType && (this as NativeScalarType).type == Bool;

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

  /// Whether the type describes complete storage rather than an opaque marker.
  bool get isSized => switch (this) {
    NativeScalarType() => !isVoid,
    NativeAbiIntegerType() => true,
    NativePointerType() || NativeCompoundType() || NativeArrayType() => true,
    NativeFunctionType() || NativeOpaqueType() => false,
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
    NativeCompoundType() ||
    NativeArrayType() ||
    NativeAbiIntegerType() ||
    NativeOpaqueType() => throw UnsupportedError(
      'Native aggregate or ABI-dependent storage requires a target layout.',
    ),
  };

  /// Formats a C declarator with [name], or an unnamed type when it is empty.
  ///
  /// ABI-specific integers require [abi] and use its fixed-width C type.
  /// [typeNames] overrides compound and opaque tags, including nested types.
  String declaration(
    String name, {
    Abi? abi,
    Map<NativeTypeRef, String> typeNames = const {},
  }) => switch (this) {
    NativeAbiIntegerType() =>
      abi == null
          ? throw ArgumentError('An ABI is required for $this.')
          : resolveAbi(abi).declaration(name),
    NativeScalarType(:final type) =>
      '${type.cType}${name.isEmpty || name.startsWith('*') ? '' : ' '}$name',
    NativePointerType(element: final NativeFunctionType function) =>
      function.declaration('(*$name)', abi: abi, typeNames: typeNames),
    NativePointerType(element: final NativeArrayType array) =>
      array.declaration('(*$name)', abi: abi, typeNames: typeNames),
    NativePointerType(:final element) => element.declaration(
      '*${name.isEmpty ? '' : ' '}$name',
      abi: abi,
      typeNames: typeNames,
    ),
    NativeFunctionType(:final signature) => signature.declaration(
      name,
      abi: abi,
      typeNames: typeNames,
    ),
    NativeCompoundType(name: final tag, :final isUnion) =>
      '${isUnion ? 'union' : 'struct'} ${typeNames[this] ?? tag}${name.isEmpty || name.startsWith('*') ? '' : ' '}$name',
    NativeOpaqueType(name: final tag) =>
      'struct ${typeNames[this] ?? tag}${name.isEmpty || name.startsWith('*') ? '' : ' '}$name',
    NativeArrayType(:final element, :final length) => element.declaration(
      '$name[${length == 0 ? '' : length}]',
      abi: abi,
      typeNames: typeNames,
    ),
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

/// A source-declared ABI integer whose mapping supplies fixed-width storage.
///
/// Its Dart identity is preserved even when two declarations have equal mappings.
final class NativeAbiIntegerType(
  final Uri library,
  final String name,
  Map<Abi, NativeScalarType> mapping,
) extends NativeTypeRef {
  /// The immutable mapping from the declaration's `AbiSpecificIntegerMapping`.
  final Map<Abi, NativeScalarType> mapping = .unmodifiable(mapping);

  this {
    if (name.isEmpty ||
        mapping.values.any(
          (value) => !{
            Int8,
            Uint8,
            Int16,
            Uint16,
            Int32,
            Uint32,
            Int64,
            Uint64,
          }.contains(value.type),
        )) {
      throw ArgumentError('ABI mappings require fixed-width integer types.');
    }
  }

  @override
  String toString() => '$library::$name';
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

/// A native field in declaration order; its offset belongs to the target ABI.
final class NativeField(final String name, final NativeTypeRef type) {
  this {
    if (name.isEmpty) {
      throw ArgumentError('Expected a native declaration name.');
    }
  }
}

/// A struct or union declaration shared by fields, pointers and signatures.
///
/// Use [NativeCompoundType.declare] and [define] for pointer-recursive declarations. The field
/// definition is immutable once supplied; by-value cycles are rejected by layout.
final class NativeCompoundType.declare(
  final String name, {
  final bool isUnion = false,
  final int? packing,
}) extends NativeTypeRef {
  factory(
    String name,
    Iterable<NativeField> fields, {
    bool isUnion = false,
    int? packing,
  }) =>
      NativeCompoundType.declare(name, isUnion: isUnion, packing: packing)
        ..define(fields);

  List<NativeField>? _fields;
  List<NativeField> get fields =>
      _fields ?? (throw StateError('Undefined native compound: $name'));

  /// Supplies the fields once, before the declaration is laid out or emitted.
  void define(Iterable<NativeField> fields) {
    if (_fields != null) {
      throw StateError('Native compound already defined: $name');
    }
    final values = List<NativeField>.unmodifiable(fields);
    final names = <String>{};
    if (values.isEmpty ||
        values.any(
          (field) =>
              field.name.isEmpty ||
              !names.add(field.name) ||
              !field.type.isSized,
        )) {
      throw ArgumentError('Expected distinct, sized native fields.');
    }
    for (final field in values.take(values.length - 1)) {
      if (field.type case NativeArrayType(variableLength: true)) {
        throw ArgumentError('A variable-length array must be the last field.');
      }
    }
    _fields = values;
  }

  this {
    if (name.isEmpty) {
      throw ArgumentError('Expected a native declaration name.');
    }
    if (packing != null && ![1, 2, 4, 8, 16].contains(packing)) {
      throw ArgumentError('Invalid native compound name or packing.');
    }
  }
}

/// Inline native array storage, used inside compound fields.
///
/// For [variableLength] arrays, [length] is the minimum storage included in
/// the enclosing layout. Additional storage is supplied by the caller.
final class NativeArrayType(
  final NativeTypeRef element,
  final int length, {
  final bool variableLength = false,
}) extends NativeTypeRef {
  this {
    if (!element.isSized || length < (variableLength ? 0 : 1)) {
      throw ArgumentError(
        'Expected sized array elements, positive fixed dimensions and a nonnegative variable dimension.',
      );
    }
    if (element case NativeArrayType(variableLength: true)) {
      throw ArgumentError('Only the outermost array dimension can vary.');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NativeArrayType &&
      element == other.element &&
      length == other.length &&
      variableLength == other.variableLength;

  @override
  int get hashCode => Object.hash(element, length, variableLength);
}

/// A native type usable through pointers without exposing its storage layout.
final class NativeOpaqueType(final String name) extends NativeTypeRef {
  this {
    if (name.isEmpty) {
      throw ArgumentError('Expected a native declaration name.');
    }
  }
}
