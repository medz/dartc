import 'dart:ffi';

/// Layout and C spelling of the supported fixed-width native scalar types.
extension NativeTypeLayout on Type {
  /// Whether this is a supported native floating-point scalar.
  bool get isFloating => this == Float || this == Double;

  /// Integer storage, signedness and its corresponding pointer type, if any.
  ({int bytes, bool signed, Type pointer})? get integerLayout =>
      _integers[this];

  /// The pointer type for a supported scalar, or null.
  Type? get pointerType {
    if (this == Void) return Pointer<Void>;
    if (this == Float) return Pointer<Float>;
    if (this == Double) return Pointer<Double>;
    return integerLayout?.pointer;
  }

  /// The native scalar element of a supported pointer, or null.
  Type? get pointerElement {
    if (this == Pointer<Void>) return Void;
    if (this == Pointer<Float>) return Float;
    if (this == Pointer<Double>) return Double;
    for (final MapEntry(:key, :value) in _integers.entries) {
      if (value.pointer == this) return key;
    }
    return null;
  }

  /// Storage size without consulting the host ABI.
  ///
  /// Supported pointers use the toolchain's 64-bit targets. Unsupported types,
  /// including `Void`, throw [UnsupportedError].
  int get nativeSize {
    if (integerLayout case final layout?) return layout.bytes;
    if (this == Float) return 4;
    if (this == Double || pointerElement != null) return 8;
    throw UnsupportedError('Native scalar type: $this');
  }

  /// The C type used in a native declaration.
  String get cType {
    if (this == Void) return 'void';
    if (this == Float) return 'float';
    if (this == Double) return 'double';
    if (this == Bool) return 'bool';
    if (this == IntPtr) return 'intptr_t';
    if (this == UintPtr) return 'uintptr_t';
    if (integerLayout case final layout?) {
      return '${layout.signed ? '' : 'u'}int${layout.bytes * 8}_t';
    }
    if (pointerElement case final element?) return '${element.cType}*';
    throw UnsupportedError('Native scalar type: $this');
  }
}

const _integers = {
  Bool: (bytes: 1, signed: false, pointer: Pointer<Bool>),
  IntPtr: (bytes: 8, signed: true, pointer: Pointer<IntPtr>),
  UintPtr: (bytes: 8, signed: false, pointer: Pointer<UintPtr>),
  Int8: (bytes: 1, signed: true, pointer: Pointer<Int8>),
  Uint8: (bytes: 1, signed: false, pointer: Pointer<Uint8>),
  Int16: (bytes: 2, signed: true, pointer: Pointer<Int16>),
  Uint16: (bytes: 2, signed: false, pointer: Pointer<Uint16>),
  Int32: (bytes: 4, signed: true, pointer: Pointer<Int32>),
  Uint32: (bytes: 4, signed: false, pointer: Pointer<Uint32>),
  Int64: (bytes: 8, signed: true, pointer: Pointer<Int64>),
  Uint64: (bytes: 8, signed: false, pointer: Pointer<Uint64>),
};
