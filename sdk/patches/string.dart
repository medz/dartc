import 'dart:typed_data' show Uint16List;

import '../../lib/runtime/contracts.dart' as runtime;
import '../runtime/string.dart';

@patch
class _StringBase {
  @patch
  bool _isWhitespace(int codeUnit) => _isTwoByteWhitespace(codeUnit);

  @patch
  String _substringUncheckedNative(int startIndex, int endIndex) {
    final result = StringStorage.create(endIndex - startIndex);
    StringStorage.copy(this, startIndex, endIndex, result, 0);
    return result;
  }

  @patch
  static String _concatRangeNative(List strings, int start, int end) {
    var length = 0;
    for (var i = start; i < end; i++) {
      final piece = strings[i] as String;
      if (piece.length > StringStorage.maximumLength - length) {
        return StringStorage.create(-1);
      }
      length += piece.length;
    }
    if (length == 0) return '';
    final result = StringStorage.create(length);
    var offset = 0;
    for (var i = start; i < end; i++) {
      final piece = strings[i] as String;
      StringStorage.copy(piece, 0, piece.length, result, offset);
      offset += piece.length;
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
    final result = StringStorage.create(length);
    var offset = 0;
    for (var i = 0; i < matches.length; i++) {
      final entry = matches[i];
      if (entry is int) {
        final int start, end;
        if (entry < 0) {
          final bits = -entry;
          start = bits >> _lengthBits;
          end = start + (bits & _lengthMask);
        } else {
          start = entry;
          end = matches[++i] as int;
        }
        RangeError.checkValidRange(start, end, base.length);
        StringStorage.copy(base, start, end, result, offset);
        offset += end - start;
      } else {
        final piece = entry as String;
        StringStorage.copy(piece, 0, piece.length, result, offset);
        offset += piece.length;
      }
    }
    assert(offset == length);
    return result;
  }
}

@patch
class StringBuffer {
  @patch
  static String _create(Uint16List buffer, int length, bool isLatin1) =>
      String.fromCharCodes(buffer, 0, length);
}

@patch
class String {
  @patch
  bool get _isOneByte => this is _OneByteString;

  @patch
  factory String.fromCharCodes(Iterable<int> charCodes, [int start, int? end]) {
    RangeError.checkNotNegative(start, 'start');
    if (end != null && end < start) {
      throw RangeError.range(end, start, null, 'end');
    }
    if (end == start) return '';
    // VM class IDs do not describe target lists; use the generic SDK path.
    return _StringBase._createStringFromIterable(charCodes, start, end);
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
    return StringStorage.read(this, index);
  }

  @patch
  String operator [](int index) => String.fromCharCode(codeUnitAt(index));

  @patch
  String operator +(String other) {
    final result = StringStorage.create(length + other.length);
    StringStorage.copy(this, 0, length, result, 0);
    StringStorage.copy(other, 0, other.length, result, length);
    return result;
  }

  @patch
  String operator *(int times) {
    if (times <= 0 || isEmpty) return '';
    if (times == 1) return this;
    final result = StringStorage.create(
      times > StringStorage.maximumLength ~/ length ? -1 : length * times,
    );
    for (var offset = 0; offset < result.length; offset += length) {
      StringStorage.copy(this, 0, length, result, offset);
    }
    return result;
  }

  @patch
  String padLeft(int width, [String padding]) =>
      width <= length || padding.isEmpty
      ? this
      : padding * (width - length) + this;

  @patch
  String padRight(int width, [String padding]) =>
      width <= length || padding.isEmpty
      ? this
      : this + padding * (width - length);

  @patch
  int get hashCode {
    var hash = 0;
    for (var i = 0; i < length; i++) {
      hash = (hash * 31 + StringStorage.read(this, i)) & 0x3fffffff;
    }
    return hash;
  }
}

// Both target storage classes use UTF-16; Latin-1 retains its SDK type invariant.
final class _OneByteString extends _StringBase {
  factory _OneByteString._uninstantiable() => throw UnsupportedError('String');

  @runtime.Primitive(.allocatePayload)
  external static _OneByteString _storage(int bytes);

  static _OneByteString _allocate(int length) {
    final result = _storage(StringStorage.bytesFor(length));
    StringStorage.initialize(result, length);
    return result;
  }

  void _setAt(int index, int codePoint) {
    assert(codePoint >= 0 && codePoint <= 0xff);
    StringStorage.write(this, index, codePoint);
  }

  static _OneByteString _allocateFromOneByteList(
    List<int> list,
    int start,
    int end,
  ) {
    final result = _allocate(end - start);
    for (var i = start; i < end; i++) {
      result._setAt(i - start, list[i]);
    }
    return result;
  }

  int _setRange(int index, String source, int start, int end) {
    StringStorage.copy(source, start, end, this, index);
    return index + end - start;
  }

  static String _concatAll(List strings, int totalLength) =>
      _StringBase._concatRangeNative(strings, 0, strings.length);

  @override
  Type get runtimeType => String;
}

final class _TwoByteString extends _StringBase {
  factory _TwoByteString._uninstantiable() => throw UnsupportedError('String');

  @runtime.Primitive(.allocatePayload)
  external static _TwoByteString _storage(int bytes);

  static _TwoByteString _allocate(int length) {
    final result = _storage(StringStorage.bytesFor(length));
    StringStorage.initialize(result, length);
    return result;
  }

  void _setAt(int index, int codePoint) {
    assert(codePoint >= 0 && codePoint <= 0xffff);
    StringStorage.write(this, index, codePoint);
  }

  static String _allocateFromTwoByteList(List<int> list, int start, int end) {
    final result = _allocate(end - start);
    for (var i = start; i < end; i++) {
      result._setAt(i - start, list[i]);
    }
    return result;
  }

  @override
  Type get runtimeType => String;
}
