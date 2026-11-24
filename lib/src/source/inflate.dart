import 'dart:typed_data';

/// Decompresses [data], which is as RFC 1951 tells.
///
/// The standalone compiler has its libraries so. It does not depend on `zlib`,
/// so that it can compile itself.
Uint8List inflate(Uint8List data) => _Inflater(data).run();

final class _Inflater(final Uint8List _data) {
  int _at = 0, _bits = 0, _count = 0;
  var _output = Uint8List(1 << 16);
  int _length = 0;

  Uint8List run() {
    bool isLast;
    do {
      isLast = _take(1) == 1;
      switch (_take(2)) {
        case 0:
          _copyStored();
        case 1:
          _copyCoded(_fixed, _fixedDistances);
        case 2:
          _copyDynamic();
        default:
          throw const FormatException('Unknown kind of block.');
      }
    } while (!isLast);
    return Uint8List.sublistView(_output, 0, _length);
  }

  /// The next [count] bits, of which the first is the lowest, or zeros after
  /// the end. They stay where they are.
  int _peek(int count) {
    while (_count < count) {
      final byte = _at < _data.length ? _data[_at] : 0;
      _bits |= byte << _count;
      _at++;
      _count += 8;
    }
    return _bits & ((1 << count) - 1);
  }

  void _skip(int count) {
    _bits >>= count;
    _count -= count;
    if (_at - (_count >> 3) > _data.length) {
      throw const FormatException('The end is missing.');
    }
  }

  int _take(int count) {
    final value = _peek(count);
    _skip(count);
    return value;
  }

  int _symbol(_Code code) {
    final entry = code.entries[_peek(code.bits)];
    if (entry == 0) throw const FormatException('Unknown code.');
    _skip(entry & 15);
    return entry >> 4;
  }

  void _add(int byte) {
    if (_length == _output.length) {
      _output = Uint8List(_length * 2)..setRange(0, _length, _output);
    }
    _output[_length++] = byte;
  }

  /// Copies bytes that are there as they are, from the next byte on.
  void _copyStored() {
    _skip(_count & 7);
    final length = _take(16);
    if (_take(16) != length ^ 0xffff) {
      throw const FormatException('Wrong length.');
    }
    for (var i = 0; i < length; i++) {
      _add(_take(8));
    }
  }

  void _copyDynamic() {
    final symbols = _take(5) + 257, distances = _take(5) + 1;
    final lengths = List.filled(19, 0);
    final count = _take(4) + 4;
    for (final at in _lengthOrder.take(count)) {
      lengths[at] = _take(3);
    }
    final code = _Code(lengths);
    final all = <int>[];
    while (all.length < symbols + distances) {
      final symbol = _symbol(code);
      final (value, repeats) = switch (symbol) {
        < 16 => (symbol, 1),
        16 when all.isNotEmpty => (all.last, 3 + _take(2)),
        17 => (0, 3 + _take(3)),
        18 => (0, 11 + _take(7)),
        _ => throw const FormatException('Nothing to repeat.'),
      };
      for (var i = 0; i < repeats; i++) {
        all.add(value);
      }
    }
    if (all.length > symbols + distances) {
      throw const FormatException('Too many lengths.');
    }
    _copyCoded(_Code(all.sublist(0, symbols)), _Code(all.sublist(symbols)));
  }

  void _copyCoded(_Code code, _Code distances) {
    while (true) {
      final symbol = _symbol(code);
      if (symbol < 256) {
        _add(symbol);
        continue;
      }
      if (symbol == 256) return;
      final (base, extra) = _rangeOf(_lengths, symbol - 257);
      final length = base + _take(extra);
      final (first, more) = _rangeOf(_distances, _symbol(distances));
      final from = _length - first - _take(more);
      if (from < 0) throw const FormatException('A copy of nothing.');
      for (var i = 0; i < length; i++) {
        _add(_output[from + i]);
      }
    }
  }

  static (int, int) _rangeOf(List<(int, int)> ranges, int at) =>
      at < ranges.length
      ? ranges[at]
      : throw const FormatException('Unknown length.');
}

/// What the next [bits] bits start with: a symbol, and the bits it takes in the
/// low four, or 0.
final class _Code(List<int> lengths) {
  late final int bits;
  late final Uint16List entries;

  this {
    var longest = 0;
    for (final length in lengths) {
      if (length > longest) longest = length;
    }
    bits = longest;
    entries = Uint16List(1 << longest);
    var next = 0;
    for (var length = 1; length <= longest; length++) {
      for (final (symbol, own) in lengths.indexed) {
        if (own != length) continue;
        if (next >> length != 0) {
          throw const FormatException('Too many codes.');
        }
        _enter(symbol, next, length);
        next++;
      }
      next <<= 1;
    }
  }

  /// Codes start with their highest bit.
  void _enter(int symbol, int code, int length) {
    var first = 0;
    for (var bit = 0; bit < length; bit++) {
      first |= (code >> bit & 1) << (length - 1 - bit);
    }
    for (var at = first; at < entries.length; at += 1 << length) {
      entries[at] = symbol << 4 | length;
    }
  }
}

const _lengthOrder = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15, //
];

final _fixed = _Code([
  ...List.filled(144, 8),
  ...List.filled(112, 9),
  ...List.filled(24, 7),
  ...List.filled(8, 8),
]);
final _fixedDistances = _Code(List.filled(30, 5));

/// The shortest length that each symbol from 257 on stands for, and how many
/// more bits follow.
final _lengths = [
  ..._ranges(first: 3, single: 8, each: 4, count: 28),
  (258, 0),
];

/// As above, for distances.
final _distances = _ranges(first: 1, single: 4, each: 2, count: 30);

/// Adjacent ranges from [first] on. There are [single] of one value, and then
/// [each] of two, four and so on.
List<(int, int)> _ranges({
  required int first,
  required int single,
  required int each,
  required int count,
}) {
  final ranges = <(int, int)>[];
  var start = first;
  for (var i = 0; i < count; i++) {
    final extra = i < single ? 0 : (i - single) ~/ each + 1;
    ranges.add((start, extra));
    start += 1 << extra;
  }
  return ranges;
}
