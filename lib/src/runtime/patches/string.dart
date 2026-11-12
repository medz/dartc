import '../../../layout/memory.dart';

import '../contracts.dart' as runtime;
import '../memory.dart';

@patch
class String {
  @patch
  factory String.fromCharCode(int charCode) {
    RangeError.checkValueInInterval(charCode, 0, 0x10ffff);
    final result = _StringStorage.create(charCode <= 0xffff ? 1 : 2);
    if (charCode <= 0xffff) {
      _StringStorage.write(result, 0, charCode);
    } else {
      final value = charCode - 0x10000;
      _StringStorage.write(result, 0, 0xd800 + (value >> 10));
      _StringStorage.write(result, 1, 0xdc00 + (value & 0x3ff));
    }
    return result;
  }

  @patch
  factory String.fromCharCodes(Iterable<int> charCodes, [int start, int? end]) {
    RangeError.checkNotNegative(start, 'start');
    if (end != null && end < start) {
      throw RangeError.range(end, start, null, 'end');
    }
    if (end == start) return '';
    final iterator = charCodes.iterator;
    for (var i = 0; i < start; i++) {
      if (!iterator.moveNext()) return '';
    }
    final units = <int>[];
    var take = end == null ? -1 : end - start;
    var bits = 0;
    while (take != 0 && iterator.moveNext()) {
      take--;
      final code = iterator.current;
      if (code <= 0xffff) {
        units.add(code);
        bits |= code;
      } else {
        final value = code - 0x10000;
        units
          ..add(0xd800 + (value >>> 10))
          ..add(0xdc00 + (value & 0x3ff));
        bits |= value | 0xd800;
      }
    }
    // Iterator failures take precedence over invalid values already observed.
    if (bits < 0 || bits > 0xfffff) {
      throw ArgumentError.value(charCodes, 'charCodes');
    }
    if (units.isEmpty) return '';
    final result = _StringStorage.create(units.length);
    for (var i = 0; i < units.length; i++) {
      _StringStorage.write(result, i, units[i]);
    }
    return result;
  }

  @patch
  int codeUnitAt(int index) {
    if (index < 0 || index >= length) {
      throw IndexError.withLength(
        index,
        length,
        indexable: this,
        name: 'index',
      );
    }
    return _StringStorage.read(this, index);
  }

  @patch
  String operator [](int index) => String.fromCharCode(codeUnitAt(index));

  @patch
  String operator +(String other) {
    final result = _StringStorage.create(length + other.length);
    for (var i = 0; i < length; i++) {
      _StringStorage.write(result, i, _StringStorage.read(this, i));
    }
    for (var i = 0; i < other.length; i++) {
      _StringStorage.write(result, length + i, _StringStorage.read(other, i));
    }
    return result;
  }

  @patch
  bool operator ==(Object other) {
    if (other is! String || length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (_StringStorage.read(this, i) != _StringStorage.read(other, i)) {
        return false;
      }
    }
    return true;
  }

  @patch
  int get hashCode {
    var hash = 0;
    for (var i = 0; i < length; i++) {
      hash = (hash * 31 + _StringStorage.read(this, i)) & 0x3fffffff;
    }
    return hash;
  }
}

abstract final class _StringStorage() {
  @runtime.Primitive(.allocatePayload)
  external static String _allocate(int bytes);

  static String create(int length) {
    const maximum = (0x1ffffffffffffff8 - ObjectHeader.fieldsOffset - 8) ~/ 2;
    final result = _allocate(length > maximum ? -1 : length * 2);
    Memory.write(Memory.addressOf(result) + ObjectHeader.fieldsOffset, length);
    return result;
  }

  static int read(String string, int index) {
    final address =
        Memory.addressOf(string) + ObjectHeader.fieldsOffset + 8 + index * 2;
    return Memory.readByte(address) | (Memory.readByte(address + 1) << 8);
  }

  static void write(String string, int index, int value) {
    final address =
        Memory.addressOf(string) + ObjectHeader.fieldsOffset + 8 + index * 2;
    Memory.writeByte(address, value);
    Memory.writeByte(address + 1, value >> 8);
  }
}
