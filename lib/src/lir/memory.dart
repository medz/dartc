import 'dart:typed_data';

import 'instruction.dart';

/// A broken LIR precondition: always a compiler bug, never a Dart exception.
final class LirFault(final String message) implements Exception {
  @override
  String toString() => 'LirFault: $message';
}

/// A managed object, whose references are kept apart from its plain bytes.
final class LirObject(int size) {
  final Uint8List bytes = Uint8List(size);
  final Map<int, LirObject> references = {};

  bool _holdsReference(int offset, int length) => references.keys.any(
    (slot) => slot < offset + length && offset < slot + Width.ref.bytes,
  );
}

/// Simulated storage that rejects accesses a real machine would corrupt.
final class LirMemory() {
  final _regions = <int, ({Uint8List bytes, bool writable})>{};
  int _next = 0x10000;

  /// Adds native bytes and returns their address.
  int map(Uint8List bytes, {bool writable = true}) {
    final address = _next;
    _regions[address] = (bytes: bytes, writable: writable);
    // The unmapped gap makes an access past the end fail.
    _next = (address + bytes.length + 0x1000) & ~0xfff;
    return address;
  }

  /// Copies [length] native bytes from [address].
  Uint8List read(int address, int length) {
    final (view, at) = _native(address, length, write: false);
    return Uint8List.sublistView(view, at, at + length);
  }

  /// Reads a value at [offset] from [base], an object or a native address.
  Object? load(Width width, Object? base, int offset) {
    if (base is! LirObject) {
      final address = _address(base, offset);
      final (view, at) = _native(address, width.bytes, write: false);
      return _decode(width, view, at);
    }
    _checkBounds(base, offset, width);
    if (width == .ref) {
      final found = base.references[offset];
      if (found == null) _checkNoReferenceBits(base, offset);
      return found;
    }
    if (base._holdsReference(offset, width.bytes)) {
      throw LirFault('A reference is read as plain bytes.');
    }
    return _decode(width, ByteData.sublistView(base.bytes), offset);
  }

  /// Writes [value] at [offset] from [base].
  void store(Width width, Object? base, int offset, Object? value) {
    if (base is! LirObject) {
      final address = _address(base, offset);
      final (view, at) = _native(address, width.bytes, write: true);
      _encode(width, view, at, value);
      return;
    }
    _checkBounds(base, offset, width);
    if (width == .ref) {
      if (!base.references.containsKey(offset)) {
        _checkNoReferenceBits(base, offset);
      }
      if (value == null) {
        base.references.remove(offset);
      } else {
        base.references[offset] = value as LirObject;
      }
      return;
    }
    if (base._holdsReference(offset, width.bytes)) {
      throw LirFault('Plain bytes overwrite a reference.');
    }
    _encode(width, ByteData.sublistView(base.bytes), offset, value);
  }

  int _address(Object? base, int offset) => base == null
      ? throw LirFault('Null dereference.')
      : (base as int) + offset;

  (ByteData, int) _native(int address, int length, {required bool write}) {
    for (final MapEntry(key: start, value: region) in _regions.entries) {
      final at = address - start;
      if (at < 0 || length < 0 || at + length > region.bytes.length) continue;
      if (write && !region.writable) {
        throw LirFault('Write to read-only address $address.');
      }
      return (ByteData.sublistView(region.bytes), at);
    }
    throw LirFault('Invalid address $address.');
  }

  void _checkBounds(LirObject object, int offset, Width width) {
    if (offset < 0 || offset + width.bytes > object.bytes.length) {
      throw LirFault('Offset $offset is outside the object.');
    }
  }

  /// A reference slot without a reference must hold null's zero bytes.
  void _checkNoReferenceBits(LirObject object, int offset) {
    if (offset % Width.ref.bytes != 0) {
      throw LirFault('Unaligned reference at $offset.');
    }
    for (var i = offset; i < offset + Width.ref.bytes; i++) {
      if (object.bytes[i] != 0) {
        throw LirFault('Plain bytes are used as a reference.');
      }
    }
  }

  Object _decode(Width width, ByteData data, int at) => switch (width) {
    .i8 => data.getInt8(at),
    .u8 => data.getUint8(at),
    .i16 => data.getInt16(at, .little),
    .u16 => data.getUint16(at, .little),
    .i32 => data.getInt32(at, .little),
    .u32 => data.getUint32(at, .little),
    .i64 || .ptr => data.getInt64(at, .little),
    .f32 => data.getFloat32(at, .little),
    .f64 => data.getFloat64(at, .little),
    .ref => throw LirFault('A reference is read outside an object.'),
  };

  void _encode(Width width, ByteData data, int at, Object? value) {
    switch (width) {
      case .i8 || .u8:
        data.setInt8(at, value as int);
      case .i16 || .u16:
        data.setInt16(at, value as int, .little);
      case .i32 || .u32:
        data.setInt32(at, value as int, .little);
      case .i64 || .ptr:
        data.setInt64(at, value as int, .little);
      case .f32:
        data.setFloat32(at, value as double, .little);
      case .f64:
        data.setFloat64(at, value as double, .little);
      case .ref:
        throw LirFault('A reference is written outside an object.');
    }
  }
}
