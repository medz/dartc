// The blocks of compressed streams.

/// Writes blocks of bytes and matches, each as short as it can be.
final class _BlockWriter {
  final int _size;

  /// Whether the codes are always the ones that are known.
  bool isFixed = false;

  _BlockWriter(this._size)
    : _values = Uint16List(_size),
      _distances = Uint16List(_size);

  /// What is in the block: bytes, or lengths with their distances.
  final Uint16List _values, _distances;
  int _count = 0;
  Int32List _lengthUses = Int32List(286), _distanceUses = Int32List(30);

  Uint8List _out = Uint8List(1 << 12);
  int _end = 0, _bits = 0, _bitCount = 0;

  bool get isUsed => _count > 0;
  bool get isFull => _count >= _size - 1;

  /// What was written, but for a part of a byte, or null if there is nothing.
  Uint8List? take() {
    if (_end == 0) return null;
    final result = Uint8List.sublistView(_out, 0, _end).sublist(0);
    _end = 0;
    return result;
  }

  void write(int value, int count) {
    _bits |= value << _bitCount;
    _bitCount += count;
    while (_bitCount >= 8) {
      if (_end == _out.length) {
        _out = Uint8List(_end * 2)..setRange(0, _end, _out);
      }
      _out[_end++] = _bits;
      _bits >>= 8;
      _bitCount -= 8;
    }
  }

  void writeBig(int value) {
    for (var shift = 24; shift >= 0; shift -= 8) {
      write(value >> shift & 0xff, 8);
    }
  }

  /// Fills a byte that was started.
  void toByte() {
    if (_bitCount > 0) write(0, 8 - _bitCount);
  }

  void addByte(int byte) {
    _values[_count] = byte;
    _distances[_count++] = 0;
    _lengthUses[byte]++;
  }

  void addMatch(int length, int distance) {
    _values[_count] = length;
    _distances[_count++] = distance;
    _lengthUses[257 + _lengthCode(length)]++;
    _distanceUses[_distanceCode(distance)]++;
  }

  static final Uint8List _lengthCodes = _makeLengthCodes();

  static Uint8List _makeLengthCodes() {
    final codes = Uint8List(259);
    for (var code = 0; code < 29; code++) {
      final base = _Inflater._lengthBases[code];
      final end = base + (1 << _Inflater._lengthBits[code]);
      for (var length = base; length < end && length < 259; length++) {
        codes[length] = code;
      }
    }
    codes[258] = 28;
    return codes;
  }

  static int _lengthCode(int length) => _lengthCodes[length];

  static int _distanceCode(int distance) {
    if (distance < 5) return distance - 1;
    final high = (distance - 1).bitLength - 1;
    return high * 2 + ((distance - 1) >> (high - 1) & 1);
  }

  static int _distanceBits(int code) => code < 2 ? 0 : (code >> 1) - 1;

  /// Stores the bytes from [start] to [end] of [window] as they are.
  void store(Uint8List window, int start, int end, {required bool isLast}) {
    var at = start;
    do {
      final left = end - at, length = left < 65535 ? left : 65535;
      write(isLast && length == left ? 1 : 0, 3);
      toByte();
      write(length, 16);
      write(~length & 0xffff, 16);
      for (var i = 0; i < length; i++) {
        write(window[at + i], 8);
      }
      at += length;
    } while (at < end);
  }

  /// Ends the block, which is of the bytes from [start] to [end] of [window] if
  /// they are still there.
  void end(Uint8List? window, int start, int end, {required bool isLast}) {
    _lengthUses[256]++;
    final lengths = _codeLengths(_lengthUses, 15);
    final distances = _codeLengths(_distanceUses, 15);
    final header = _Header(lengths, distances);
    var own = header.size, known = 0;
    void count(Int32List uses, List<int> lengths, int Function(int) fixed) {
      for (var i = 0; i < uses.length; i++) {
        own += uses[i] * lengths[i];
        known += uses[i] * fixed(i);
      }
    }

    count(_lengthUses, lengths, (i) => _Inflater._fixedLengthOf(i));
    count(_distanceUses, distances, (_) => 5);
    final isKnown = isFixed || known <= own;
    final size = isKnown ? known : own;
    if (window != null && !isFixed && (end - start) * 8 + 32 <= size) {
      store(window, start, end, isLast: isLast);
    } else {
      write((isLast ? 1 : 0) | (isKnown ? 2 : 4), 3);
      if (isKnown) {
        _writeValues([
          for (var i = 0; i < 288; i++) _Inflater._fixedLengthOf(i),
        ], List.filled(30, 5));
      } else {
        header.write(this);
        _writeValues(lengths, distances);
      }
    }
    _count = 0;
    _lengthUses = Int32List(286);
    _distanceUses = Int32List(30);
  }

  void _writeValues(List<int> lengths, List<int> distances) {
    final lengthCodes = _codesOf(lengths), distanceCodes = _codesOf(distances);
    for (var i = 0; i < _count; i++) {
      final value = _values[i], distance = _distances[i];
      if (distance == 0) {
        write(lengthCodes[value], lengths[value]);
        continue;
      }
      final code = _lengthCode(value);
      write(lengthCodes[257 + code], lengths[257 + code]);
      write(value - _Inflater._lengthBases[code], _Inflater._lengthBits[code]);
      final other = _distanceCode(distance);
      write(distanceCodes[other], distances[other]);
      write(distance - _Inflater._distanceBases[other], _distanceBits(other));
    }
    write(lengthCodes[256], lengths[256]);
  }

  /// The codes that [lengths] mean, the first bit lowest.
  static List<int> _codesOf(List<int> lengths) {
    final next = List.filled(17, 0), counts = List.filled(17, 0);
    for (final length in lengths) {
      if (length > 0) counts[length]++;
    }
    for (var length = 1; length < 16; length++) {
      next[length + 1] = (next[length] + counts[length]) << 1;
    }
    return [
      for (final length in lengths)
        if (length == 0) 0 else _reversed(next[length]++, length),
    ];
  }

  static int _reversed(int code, int length) {
    var result = 0;
    for (var i = 0; i < length; i++) {
      result = result << 1 | code >> i & 1;
    }
    return result;
  }
}

/// The shortest codes for symbols with these [uses], of [longest] bits at most,
/// as their lengths.
List<int> _codeLengths(Int32List uses, int longest) {
  final lengths = List.filled(uses.length, 0);
  final used = [
    for (var i = 0; i < uses.length; i++)
      if (uses[i] > 0) i,
  ];
  if (used.length < 2) {
    // There have to be two codes.
    for (var i = 0; used.length < 2; i++) {
      if (!used.contains(i)) used.add(i);
    }
    for (final symbol in used) {
      lengths[symbol] = 1;
    }
    return lengths;
  }
  used.sort((a, b) => uses[a] != uses[b] ? uses[a] - uses[b] : a - b);
  // Two queues, of symbols and of what they were put together to.
  final count = used.length;
  final weights = [for (final symbol in used) uses[symbol]];
  final parents = List.filled(count * 2 - 1, 0);
  var symbol = 0, node = count;
  int least() {
    final isSymbol =
        symbol < count &&
        (node >= weights.length || weights[symbol] <= weights[node]);
    return isSymbol ? symbol++ : node++;
  }

  while (weights.length < count * 2 - 1) {
    final a = least(), b = least();
    parents[a] = parents[b] = weights.length;
    weights.add(weights[a] + weights[b]);
  }
  final depths = List.filled(count * 2 - 1, 0), counts = List.filled(65, 0);
  var over = 0;
  for (var i = count * 2 - 3; i >= 0; i--) {
    var depth = depths[parents[i]] + 1;
    if (depth > longest) {
      depth = longest;
      if (i < count) over++;
    }
    depths[i] = depth;
    if (i < count) counts[depth]++;
  }
  _shorten(counts, longest, over);
  // The symbols that are used least have the longest codes.
  var at = 0;
  for (var length = longest; length > 0; length--) {
    for (var i = 0; i < counts[length]; i++) {
      lengths[used[at++]] = length;
    }
  }
  return lengths;
}

/// Makes [counts], of which [over] symbols were cut to [longest] bits, those of
/// complete codes again.
void _shorten(List<int> counts, int longest, int over) {
  if (over == 0) return;
  var sum = 0;
  for (var length = 1; length <= longest; length++) {
    sum += counts[length] << (longest - length);
  }
  final full = 1 << longest;
  while (sum > full) {
    var length = longest - 1;
    while (counts[length] == 0) {
      length--;
    }
    // A code becomes two that are a bit longer, and takes one of the longest.
    counts[length]--;
    counts[length + 1] += 2;
    counts[longest]--;
    sum--;
  }
}

/// How the codes of a block are told.
final class _Header {
  final List<int> _all = [];
  late final int _lengthCount, _distanceCount;

  /// Symbols for lengths, or for how often one is there, and what tells that.
  final List<(int, int, int)> _symbols = [];
  late final List<int> _own;
  late final int _ownCount;

  _Header(List<int> lengths, List<int> distances) {
    _lengthCount = _withoutZeros(lengths, 257);
    _distanceCount = _withoutZeros(distances, 1);
    _all
      ..addAll(lengths.take(_lengthCount))
      ..addAll(distances.take(_distanceCount));
    for (var i = 0; i < _all.length;) {
      var count = 1;
      while (i + count < _all.length && _all[i + count] == _all[i]) {
        count++;
      }
      _add(_all[i], count);
      i += count;
    }
    final uses = Int32List(19);
    for (final (symbol, _, _) in _symbols) {
      uses[symbol]++;
    }
    _own = _codeLengths(uses, 7);
    var last = 18;
    while (last > 3 && _own[_Inflater._order[last]] == 0) {
      last--;
    }
    _ownCount = last + 1;
  }

  static int _withoutZeros(List<int> lengths, int least) {
    var count = lengths.length;
    while (count > least && lengths[count - 1] == 0) {
      count--;
    }
    return count;
  }

  void _add(int length, int count) {
    var left = count;
    if (length == 0) {
      while (left >= 11) {
        final now = left < 138 ? left : 138;
        _symbols.add((18, now - 11, 7));
        left -= now;
      }
      if (left >= 3) {
        _symbols.add((17, left - 3, 3));
        left = 0;
      }
    } else {
      _symbols.add((length, 0, 0));
      left--;
      while (left >= 3) {
        final now = left < 6 ? left : 6;
        _symbols.add((16, now - 3, 2));
        left -= now;
      }
    }
    for (; left > 0; left--) {
      _symbols.add((length, 0, 0));
    }
  }

  int get size {
    var bits = 14 + _ownCount * 3;
    for (final (symbol, _, count) in _symbols) {
      bits += _own[symbol] + count;
    }
    return bits;
  }

  void write(_BlockWriter to) {
    to
      ..write(_lengthCount - 257, 5)
      ..write(_distanceCount - 1, 5)
      ..write(_ownCount - 4, 4);
    for (var i = 0; i < _ownCount; i++) {
      to.write(_own[_Inflater._order[i]], 3);
    }
    final codes = _BlockWriter._codesOf(_own);
    for (final (symbol, value, count) in _symbols) {
      to
        ..write(codes[symbol], _own[symbol])
        ..write(value, count);
    }
  }
}
