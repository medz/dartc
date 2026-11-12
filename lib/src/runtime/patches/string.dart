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
    _StringStorage.copy(this, 0, length, result, 0);
    _StringStorage.copy(other, 0, other.length, result, length);
    return result;
  }

  @patch
  bool get isEmpty => length == 0;
  @patch
  bool get isNotEmpty => length != 0;
  @override
  String toString() => this;
  @patch
  Runes get runes => Runes(this);

  @patch
  String substring(int start, [int? end]) {
    final limit = RangeError.checkValidRange(start, end, length);
    if (start == 0 && limit == length) return this;
    if (start == limit) return '';
    final result = _StringStorage.create(limit - start);
    _StringStorage.copy(this, start, limit, result, 0);
    return result;
  }

  @patch
  int compareTo(String other) {
    final limit = length < other.length ? length : other.length;
    for (var i = 0; i < limit; i++) {
      final left = codeUnitAt(i), right = other.codeUnitAt(i);
      if (left != right) return left < right ? -1 : 1;
    }
    return length.compareTo(other.length);
  }

  @patch
  bool endsWith(String other) =>
      _StringStorage.matchesAt(this, other, length - other.length);

  @patch
  bool startsWith(Pattern pattern, [int index]) {
    RangeError.checkValueInInterval(index, 0, length, 'index');
    return pattern is String
        ? _StringStorage.matchesAt(this, pattern, index)
        : pattern.matchAsPrefix(this, index) != null;
  }

  @patch
  int indexOf(Pattern pattern, [int start]) {
    RangeError.checkValueInInterval(start, 0, length, 'start');
    final end = pattern is String ? length - pattern.length : length;
    for (var i = start; i <= end; i++) {
      if (pattern is String
          ? _StringStorage.matchesAt(this, pattern, i)
          : pattern.matchAsPrefix(this, i) != null)
        return i;
    }
    return -1;
  }

  @patch
  int lastIndexOf(Pattern pattern, [int? start]) {
    var index = start ?? length;
    RangeError.checkValueInInterval(index, 0, length, 'start');
    if (pattern is String && index > length - pattern.length) {
      index = length - pattern.length;
    }
    for (; index >= 0; index--) {
      if (pattern is String
          ? _StringStorage.matchesAt(this, pattern, index)
          : pattern.matchAsPrefix(this, index) != null)
        return index;
    }
    return -1;
  }

  @patch
  bool contains(Pattern other, [int startIndex]) =>
      indexOf(other, startIndex) >= 0;

  @override
  Iterable<Match> allMatches(String string, [int start = 0]) {
    RangeError.checkValueInInterval(start, 0, string.length, 'start');
    return _StringAllMatchesIterable(string, this, start);
  }

  @override
  Match? matchAsPrefix(String string, [int start = 0]) {
    RangeError.checkValueInInterval(start, 0, string.length, 'start');
    return _StringStorage.matchesAt(string, this, start)
        ? _StringMatch(start, string, this)
        : null;
  }

  @patch
  String trim() => trimLeft().trimRight();

  @patch
  String trimLeft() {
    var start = 0;
    while (start < length &&
        _StringBase._isTwoByteWhitespace(codeUnitAt(start))) {
      start++;
    }
    return substring(start);
  }

  @patch
  String trimRight() {
    var end = length;
    while (end > 0 && _StringBase._isTwoByteWhitespace(codeUnitAt(end - 1))) {
      end--;
    }
    return substring(0, end);
  }

  @patch
  String operator *(int times) {
    if (times <= 0 || isEmpty) return '';
    if (times == 1) return this;
    final result = _StringStorage.create(
      times > _StringStorage.maximumLength ~/ length ? -1 : length * times,
    );
    for (var offset = 0; offset < result.length; offset += length) {
      _StringStorage.copy(this, 0, length, result, offset);
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
  String replaceRange(int start, int? end, String replacement) {
    final limit = RangeError.checkValidRange(start, end, length);
    return _StringStorage.join([
      substring(0, start),
      replacement,
      substring(limit),
    ]);
  }

  @patch
  String replaceFirst(Pattern from, String to, [int startIndex]) {
    RangeError.checkValueInInterval(startIndex, 0, length, 'startIndex');
    final matches = from.allMatches(this, startIndex).iterator;
    if (!matches.moveNext()) return this;
    final match = matches.current;
    return replaceRange(match.start, match.end, to);
  }

  @patch
  String replaceFirstMapped(
    Pattern from,
    String Function(Match) replace, [
    int startIndex,
  ]) {
    RangeError.checkValueInInterval(startIndex, 0, length, 'startIndex');
    final matches = from.allMatches(this, startIndex).iterator;
    if (!matches.moveNext()) return this;
    final match = matches.current;
    return replaceRange(match.start, match.end, replace(match));
  }

  @patch
  String replaceAll(Pattern from, String replace) =>
      replaceAllMapped(from, (_) => replace);

  @patch
  String replaceAllMapped(Pattern from, String Function(Match) replace) {
    final pieces = <String>[];
    var start = 0;
    for (final match in from.allMatches(this)) {
      pieces.add(substring(start, match.start));
      pieces.add(replace(match));
      start = match.end;
    }
    pieces.add(substring(start));
    return _StringStorage.join(pieces);
  }

  @patch
  List<String> split(Pattern pattern) {
    if (pattern is String && pattern.isEmpty) {
      return [for (var i = 0; i < length; i++) this[i]];
    }
    final matches = pattern.allMatches(this).iterator;
    if (isEmpty && matches.moveNext()) return [];
    final pieces = <String>[];
    var scan = 0, start = 0;
    while (scan < length && matches.moveNext()) {
      final match = matches.current;
      if (match.start == length) break;
      if (scan == match.end && start == match.end) {
        scan++;
        continue;
      }
      pieces.add(substring(start, match.start));
      scan = start = match.end;
    }
    pieces.add(substring(start));
    return pieces;
  }

  @patch
  String splitMapJoin(
    Pattern pattern, {
    String Function(Match)? onMatch,
    String Function(String)? onNonMatch,
  }) {
    final pieces = <String>[];
    void matched(Match match) => pieces.add(onMatch?.call(match) ?? match[0]!);
    void unmatched(String value) =>
        pieces.add(onNonMatch?.call(value) ?? value);
    var start = 0;
    if (pattern is String && pattern.isEmpty) {
      unmatched('');
      // Empty-string splitMapJoin keeps surrogate pairs together.
      for (final rune in runes) {
        matched(_StringMatch(start, this, ''));
        final end = start + (rune > 0xffff ? 2 : 1);
        unmatched(substring(start, end));
        start = end;
      }
      matched(_StringMatch(start, this, ''));
      unmatched('');
    } else {
      for (final match in pattern.allMatches(this)) {
        unmatched(substring(start, match.start));
        matched(match);
        start = match.end;
      }
      unmatched(substring(start));
    }
    return _StringStorage.join(pieces);
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
  static const maximumLength =
      (0x1ffffffffffffff8 - ObjectHeader.fieldsOffset - 8) ~/ 2;
  @runtime.Primitive(.allocatePayload)
  external static String _allocate(int bytes);

  static String create(int length) {
    final result = _allocate(
      length < 0 || length > maximumLength ? -1 : length * 2,
    );
    Memory.write(Memory.addressOf(result) + ObjectHeader.fieldsOffset, length);
    return result;
  }

  static bool matchesAt(String source, String other, int start) {
    if (start < 0 || other.length > source.length - start) return false;
    for (var i = 0; i < other.length; i++) {
      if (source.codeUnitAt(start + i) != other.codeUnitAt(i)) return false;
    }
    return true;
  }

  static void copy(
    String source,
    int start,
    int end,
    String destination,
    int offset,
  ) {
    for (var i = start; i < end; i++) {
      write(destination, offset++, read(source, i));
    }
  }

  static String join(List<String> pieces) {
    var length = 0;
    for (final piece in pieces) {
      if (piece.length > maximumLength - length) return create(-1);
      length += piece.length;
    }
    if (length == 0) return '';
    final result = create(length);
    var offset = 0;
    for (final piece in pieces) {
      copy(piece, 0, piece.length, result, offset);
      offset += piece.length;
    }
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
