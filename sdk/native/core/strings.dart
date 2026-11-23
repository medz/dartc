import 'dart:_heap/objects.dart'
    show lengthOf, loadUint16, loadUint8, storeUint16, storeUint8;

/// What string interpolations with several parts do.
String _interpolate(List values) => _StringBase._interpolate(values);

/// What string interpolations with one part do.
String _interpolateSingle(Object? value) =>
    _StringBase._interpolateSingle(value);

int _checkIndex(int index, int length, String name) {
  if (index < 0 || index >= length) {
    throw RangeError.range(index, 0, length - 1, name);
  }
  return index;
}

@patch
class _StringBase {
  @patch
  int get hashCode;

  @patch
  int get _identityHashCode => hashCode;

  @patch
  int get length;

  @patch
  int codeUnitAt(int index);

  /// The code unit at [index], which is one.
  int _unitAt(int index);

  /// Like the official runtime's.
  int _computeHash() {
    final length = this.length;
    var hash = 0;
    for (var i = 0; i < length; i++) {
      hash = (hash + _unitAt(i)) & 0xffffffff;
      hash = (hash + (hash << 10)) & 0xffffffff;
      hash ^= hash >> 6;
    }
    hash = (hash + (hash << 3)) & 0xffffffff;
    hash ^= hash >> 11;
    hash = (hash + (hash << 15)) & 0x3fffffff;
    return hash == 0 ? 1 : hash;
  }

  /// The strings of one byte, which are the same as literals.
  static const _single = [
    '\x00', '\x01', '\x02', '\x03', '\x04', '\x05', '\x06', '\x07', //
    '\x08', '\x09', '\x0a', '\x0b', '\x0c', '\x0d', '\x0e', '\x0f', //
    '\x10', '\x11', '\x12', '\x13', '\x14', '\x15', '\x16', '\x17', //
    '\x18', '\x19', '\x1a', '\x1b', '\x1c', '\x1d', '\x1e', '\x1f', //
    ' ', '!', '"', '#', '\$', '%', '&', '\'', //
    '(', ')', '*', '+', ',', '-', '.', '/', //
    '0', '1', '2', '3', '4', '5', '6', '7', //
    '8', '9', ':', ';', '<', '=', '>', '?', //
    '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', //
    'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', //
    'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', //
    'X', 'Y', 'Z', '[', '\\', ']', '^', '_', //
    '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', //
    'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', //
    'p', 'q', 'r', 's', 't', 'u', 'v', 'w', //
    'x', 'y', 'z', '{', '|', '}', '~', '\x7f', //
    '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', //
    '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', //
    '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', //
    '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', //
    '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', //
    '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', //
    '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', //
    '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf', //
    '\xc0', '\xc1', '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', //
    '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', //
    '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', //
    '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf', //
    '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', //
    '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef', //
    '\xf0', '\xf1', '\xf2', '\xf3', '\xf4', '\xf5', '\xf6', '\xf7', //
    '\xf8', '\xf9', '\xfa', '\xfb', '\xfc', '\xfd', '\xfe', '\xff', //
  ];

  static String _ofUnit(int unit) {
    if (unit > 255) return _TwoByteString._allocate(1).._setAt(0, unit);
    return _single[unit];
  }

  @patch
  String operator [](int index) =>
      _ofUnit(_unitAt(_checkIndex(index, length, 'index')));

  @patch
  String operator +(String other) {
    final length = this.length, rest = other.length;
    if (length == 0) return other;
    if (rest == 0) return this;
    if (this is _OneByteString && other is _OneByteString) {
      final result = _OneByteString._allocate(length + rest);
      _copyTo(result, 0);
      unsafeCast<_OneByteString>(other)._copyTo(result, length);
      return result;
    }
    final result = _TwoByteString._allocate(length + rest);
    _copyTo(result, 0);
    unsafeCast<_StringBase>(other)._copyTo(result, length);
    return result;
  }

  /// Copies all code units into [to], from [at].
  void _copyTo(_StringBase to, int at) {
    final length = this.length;
    if (to is _OneByteString) {
      for (var i = 0; i < length; i++) {
        storeUint8(to, at + i, _unitAt(i));
      }
    } else {
      for (var i = 0; i < length; i++) {
        storeUint16(to, (at + i) * 2, _unitAt(i));
      }
    }
  }

  /// The code units from [start] to [end], one byte each if they all fit.
  @patch
  String _substringUncheckedNative(int startIndex, int endIndex) {
    final length = endIndex - startIndex;
    var bits = 0;
    for (var i = startIndex; i < endIndex; i++) {
      bits |= _unitAt(i);
    }
    if (bits < 256) {
      final result = _OneByteString._allocate(length);
      for (var i = 0; i < length; i++) {
        storeUint8(result, i, _unitAt(startIndex + i));
      }
      return result;
    }
    final result = _TwoByteString._allocate(length);
    for (var i = 0; i < length; i++) {
      storeUint16(result, i * 2, _unitAt(startIndex + i));
    }
    return result;
  }

  @patch
  static String _createFromCodePoints(
    List<int> codePoints,
    int start,
    int end,
  ) {
    var length = 0, bits = 0;
    for (var i = start; i < end; i++) {
      final point = codePoints[i];
      if (point < 0 || point > 0x10ffff) throw ArgumentError(codePoints);
      bits |= point;
      length += point > 0xffff ? 2 : 1;
    }
    if (bits < 256) return _createOneByteString(codePoints, start, end - start);
    final result = _TwoByteString._allocate(length);
    var at = 0;
    for (var i = start; i < end; i++) {
      final point = codePoints[i];
      if (point > 0xffff) {
        result._setAt(at++, 0xd7c0 + (point >> 10));
        result._setAt(at++, 0xdc00 + (point & 0x3ff));
      } else {
        result._setAt(at++, point);
      }
    }
    return result;
  }

  @patch
  static String _concatRangeNative(List strings, int start, int end) {
    var length = 0, isNarrow = true;
    for (var i = start; i < end; i++) {
      final string = unsafeCast<_StringBase>(strings[i]);
      length += string.length;
      if (string is! _OneByteString && string.length > 0) isNarrow = false;
    }
    final _StringBase result = isNarrow
        ? _OneByteString._allocate(length)
        : _TwoByteString._allocate(length);
    var at = 0;
    for (var i = start; i < end; i++) {
      final string = unsafeCast<_StringBase>(strings[i]);
      string._copyTo(result, at);
      at += string.length;
    }
    return result;
  }

  @patch
  static String _joinReplaceAllResult(
    String base,
    List matches,
    int length,
    bool replacementStringsAreOneByte,
  ) {
    final parts = [];
    for (var i = 0; i < matches.length; i++) {
      final part = matches[i];
      if (part is String) {
        parts.add(part);
        continue;
      }
      // Slices are a negative number, or where they start and end.
      int start = part, end;
      if (start < 0) {
        final bits = -start;
        start = bits >> _lengthBits;
        end = start + (bits & _lengthMask);
      } else {
        end = matches[++i];
      }
      parts.add(base.substring(start, end));
    }
    return _concatRangeNative(parts, 0, parts.length);
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _OneByteString {
  int _hash = 0;

  @patch
  int get hashCode {
    if (_hash == 0) _hash = _computeHash();
    return _hash;
  }

  int get length => lengthOf(this);
  int codeUnitAt(int index) =>
      loadUint8(this, _checkIndex(index, lengthOf(this), 'length'));
  int _unitAt(int index) => loadUint8(this, index);

  @patch
  String _substringUncheckedNative(int startIndex, int endIndex) {
    final length = endIndex - startIndex;
    final result = _OneByteString._allocate(length);
    for (var i = 0; i < length; i++) {
      storeUint8(result, i, loadUint8(this, startIndex + i));
    }
    return result;
  }

  @patch
  static _OneByteString _allocateFromOneByteList(
    List<int> list,
    int start,
    int end,
  ) {
    final result = _OneByteString._allocate(end - start);
    for (var i = start; i < end; i++) {
      storeUint8(result, i - start, list[i]);
    }
    return result;
  }
}

@patch
@pragma('dartc:elements', 'bytes')
class _TwoByteString {
  int _hash = 0;

  int get hashCode {
    if (_hash == 0) _hash = _computeHash();
    return _hash;
  }

  int get length => lengthOf(this) >> 1;
  int codeUnitAt(int index) =>
      loadUint16(this, _checkIndex(index, length, 'length') * 2);
  int _unitAt(int index) => loadUint16(this, index * 2);

  @patch
  static String _allocateFromTwoByteList(List<int> list, int start, int end) {
    final result = _TwoByteString._allocate(end - start);
    for (var i = start; i < end; i++) {
      storeUint16(result, (i - start) * 2, list[i]);
    }
    return result;
  }
}

@patch
class StringBuffer {
  @patch
  static String _create(Uint16List buffer, int length, bool isLatin1) =>
      isLatin1
      ? _OneByteString._allocateFromOneByteList(buffer, 0, length)
      : _TwoByteString._allocateFromTwoByteList(buffer, 0, length);
}
