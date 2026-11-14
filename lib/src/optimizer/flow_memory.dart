import 'dart:ffi' show Uint8;
import 'dart:typed_data';

import 'package:dartc/abi.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/layout.dart';
import 'package:dartc/interop.dart';

import 'flow_value.dart';
import 'state_map.dart';

/// Byte facts for one allocation, without materializing its unused zeroes.
final class FlowMemory {
  final int start;
  final int? length;
  final List<(int, int)> _zeroes;
  final StateMap<int, _Byte> _bytes;
  final FlowValue _retained;

  new(this.start, this.length)
    : _zeroes = length == null || length == 0
          ? const []
          : [(start, start + length)],
      _bytes = const .empty(),
      _retained = const .bottom();

  new _(this.start, this.length, this._zeroes, this._bytes, this._retained);

  bool contains(int offset, int size) =>
      size >= 0 &&
      offset >= start &&
      length != null &&
      offset - start <= length! &&
      size <= length! - (offset - start);

  FlowValue get references {
    var value = _retained;
    for (final byte in _bytes.values) {
      value = value.join(byte.references);
    }
    return value;
  }

  _Byte _defaultAt(int offset) =>
      _zeroes.any((r) => r.$1 <= offset && offset < r.$2) ? _zero : _unknown;

  _Byte _at(int offset) => _bytes[offset] ?? _defaultAt(offset);

  FlowValue read(int offset, NativeTypeRef storage, NativeLayout layout) {
    final type = storage.resolveAbi(layout.target.abi);
    final size = layout.of(type).size;
    if (!contains(offset, size)) {
      return FlowValue.unknown(FfiTypes.valueType(type))
          .withReferences([references]);
    }
    final bytes = [for (var i = 0; i < size; i++) _at(offset + i)];
    final data = ByteData(size);
    var constant = true;
    for (var i = 0; i < size; i++) {
      if (bytes[i].value.constant case ScalarConstant(value: final int value)
          when bytes[i].type == _uint8) {
        data.setUint8(i, value);
      } else {
        constant = false;
        break;
      }
    }
    if (constant) {
      final endian = layout.target.byteOrder;
      if (type.isFloating) {
        return .constant(
          Constant.floating(
            type.isSinglePrecision
                ? data.getFloat32(0, endian)
                : data.getFloat64(0, endian),
          ),
        );
      }
      if (type.isBoolean) {
        return .constant(Constant.boolean(data.getUint8(0) != 0));
      }
      final integer = type.integerLayout!;
      final bits = switch (size) {
        1 => data.getUint8(0),
        2 => data.getUint16(0, endian),
        4 => data.getUint32(0, endian),
        _ => data.getInt64(0, endian),
      };
      return .constant(
        Constant.integer(integer.signed ? bits.toSigned(size * 8) : bits),
      );
    }
    final first = bytes.first;
    if (first.type == type &&
        (size == 8 || type.isBoolean) &&
        bytes.indexed.every(
          (e) =>
              e.$2.type == type &&
              e.$2.index == e.$1 &&
              e.$2.value == first.value,
        )) {
      return first.value;
    }
    return FlowValue.unknown(FfiTypes.valueType(type))
        .withReferences([_retained, for (final byte in bytes) byte.value]);
  }

  /// Reads a complete traced slot; partial bytes never become a Dart value.
  FlowValue? readReference(int offset) {
    if (offset % ObjectHeader.alignment != 0 ||
        !contains(offset, ObjectHeader.alignment)) {
      return null;
    }
    final bytes = [
      for (var i = 0; i < ObjectHeader.alignment; i++) _at(offset + i),
    ];
    if (bytes.every((byte) => byte == _zero)) return _null;
    final first = bytes.first;
    return first.type == null &&
            bytes.indexed.every(
              (entry) =>
                  entry.$2.type == null &&
                  entry.$2.index == entry.$1 &&
                  entry.$2.value == first.value,
            )
        ? first.value
        : null;
  }

  /// Stores the language value, including boxed scalars, in one traced slot.
  FlowMemory writeReference(int offset, FlowValue value) {
    if (offset % ObjectHeader.alignment != 0 ||
        !contains(offset, ObjectHeader.alignment)) {
      return invalidate();
    }
    var bytes = _bytes;
    for (var i = 0; i < ObjectHeader.alignment; i++) {
      bytes = bytes.withEntry(offset + i, _Byte(value, null, i));
    }
    return FlowMemory._(start, length, _zeroes, bytes, _retained);
  }

  FlowMemory write(
    int offset,
    NativeTypeRef storage,
    FlowValue value,
    NativeLayout layout,
  ) {
    final type = storage.resolveAbi(layout.target.abi);
    final size = layout.of(type).size;
    if (!contains(offset, size)) return invalidate();
    final data = ByteData(size);
    final constant = value.constant;
    if (constant case ScalarConstant(value: final double number)) {
      if (type.isSinglePrecision) {
        data.setFloat32(0, number, layout.target.byteOrder);
      } else {
        data.setFloat64(0, number, layout.target.byteOrder);
      }
    } else if (constant case ScalarConstant(value: final bool boolean)) {
      data.setUint8(0, boolean ? 1 : 0);
    } else if (constant case ScalarConstant(value: final int integer)) {
      for (var i = 0; i < size; i++) {
        final shift = layout.target.byteOrder == Endian.little
            ? i
            : size - 1 - i;
        data.setUint8(i, (integer >>> (shift * 8)) & 0xff);
      }
    }
    var bytes = _bytes;
    for (var i = 0; i < size; i++) {
      final byte = constant is ScalarConstant
          ? _Byte(.constant(Constant.integer(data.getUint8(i))), _uint8, 0)
          : _Byte(value, type, i);
      bytes = byte == _defaultAt(offset + i)
          ? bytes.withoutKey(offset + i)
          : bytes.withEntry(offset + i, byte);
    }
    return FlowMemory._(start, length, _zeroes, bytes, _retained);
  }

  /// Forgets only the overwritten range and preserves disjoint storage.
  FlowMemory forget(
    int offset,
    int size, {
    FlowValue retained = const .bottom(),
  }) {
    if (!contains(offset, size)) return invalidate();
    final end = offset + size;
    final zeroes = <(int, int)>[];
    for (final (low, high) in _zeroes) {
      if (high <= offset || low >= end) {
        zeroes.add((low, high));
      } else {
        if (low < offset) zeroes.add((low, offset));
        if (high > end) zeroes.add((end, high));
      }
    }
    var bytes = _bytes;
    for (final key in _bytes.keys) {
      if (offset <= key && key < end) bytes = bytes.withoutKey(key);
    }
    return FlowMemory._(start, length, zeroes, bytes, _retained.join(retained));
  }

  /// Copies the source snapshot, including overlap, in work proportional to facts.
  FlowMemory copyFrom(int offset, FlowMemory source, int from, int size) {
    final cleared = forget(offset, size, retained: source._retained);
    if (!contains(offset, size) || !source.contains(from, size)) return cleared;
    final shift = offset - from;
    final zeroes = [...cleared._zeroes];
    for (final (low, high) in source._zeroes) {
      final begin = low > from ? low : from;
      final finish = high < from + size ? high : from + size;
      if (begin < finish) zeroes.add((begin + shift, finish + shift));
    }
    zeroes.sort((a, b) => a.$1.compareTo(b.$1));
    var bytes = cleared._bytes;
    for (final entry in source._bytes.entries) {
      if (from <= entry.key && entry.key < from + size) {
        bytes = bytes.withEntry(entry.key + shift, entry.value);
      }
    }
    return FlowMemory._(
      start,
      length,
      _coalesce(zeroes),
      bytes,
      cleared._retained,
    );
  }

  FlowMemory invalidate() =>
      FlowMemory._(start, length, const [], const .empty(), references);

  FlowMemory map(FlowValue Function(FlowValue) transform) {
    final bytes = _bytes.mapValues(
      (_, byte) => _Byte(transform(byte.value), byte.type, byte.index),
    );
    final retained = transform(_retained);
    return identical(bytes, _bytes) && retained == _retained
        ? this
        : FlowMemory._(start, length, _zeroes, bytes, retained);
  }

  FlowMemory join(FlowMemory other) {
    if (this == other) return this;
    if (start != other.start) {
      throw StateError('One allocation has incompatible native storage.');
    }
    final zeroes = <(int, int)>[];
    var left = 0, right = 0;
    while (left < _zeroes.length && right < other._zeroes.length) {
      final a = _zeroes[left], b = other._zeroes[right];
      final low = a.$1 > b.$1 ? a.$1 : b.$1;
      final high = a.$2 < b.$2 ? a.$2 : b.$2;
      if (low < high) zeroes.add((low, high));
      if (a.$2 < b.$2) {
        left++;
      } else {
        right++;
      }
    }
    final merged = FlowMemory._(
      start,
      length == null || other.length == null
          ? null
          : length! < other.length!
          ? length
          : other.length,
      _coalesce(zeroes),
      const .empty(),
      _retained.join(other._retained),
    );
    final bytes = _bytes.merge(other._bytes, (key, a, b) {
      final byte = (a ?? _at(key)).join(b ?? other._at(key));
      return byte == merged._at(key) ? null : byte;
    });
    return FlowMemory._(
      start,
      merged.length,
      merged._zeroes,
      bytes,
      merged._retained,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlowMemory &&
          start == other.start &&
          length == other.length &&
          _bytes == other._bytes &&
          _retained == other._retained &&
          _zeroes.length == other._zeroes.length &&
          _zeroes.indexed.every((e) => e.$2 == other._zeroes[e.$1]);

  @override
  late final int hashCode = Object.hash(
    start,
    length,
    Object.hashAll(_zeroes),
    _bytes,
    _retained,
  );
}

final class _Byte(
  final FlowValue value,
  // A null native type denotes a traced reference fragment.
  final NativeTypeRef? type,
  final int index,
) {
  FlowValue get references => type == null ? value : value.references;

  _Byte join(_Byte other) {
    if (type == other.type && index == other.index) {
      return _Byte(value.join(other.value), type, index);
    }
    if (type == null && other == _zero) {
      return _Byte(value.join(_null), null, index);
    }
    if (this == _zero && other.type == null) {
      return _Byte(_null.join(other.value), null, other.index);
    }
    return _Byte(
      FlowValue.unknown(.integer)
          .withReferences([references, other.references]),
      _uint8,
      0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _Byte &&
      type == other.type &&
      index == other.index &&
      value == other.value;

  @override
  int get hashCode => Object.hash(value, type, index);
}

final _null = FlowValue.constant(const Constant.nullValue());
final _uint8 = NativeScalarType(Uint8);
final _zero = _Byte(.constant(const Constant.integer(0)), _uint8, 0);
final _unknown = _Byte(.unknown(.integer), _uint8, 0);

List<(int, int)> _coalesce(List<(int, int)> ranges) {
  final result = <(int, int)>[];
  for (final range in ranges) {
    if (result.isNotEmpty && range.$1 <= result.last.$2) {
      if (range.$2 > result.last.$2) {
        result[result.length - 1] = (result.last.$1, range.$2);
      }
    } else {
      result.add(range);
    }
  }
  return List.unmodifiable(result);
}
