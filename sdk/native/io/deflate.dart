// Compression, as RFC 1950 to 1952 tell.

/// Compresses a stream that comes in pieces, by finding what was there before.
final class _Deflater {
  final int _level, _strategy, _windowBits;
  final _Wrapping _wrapping;
  final List<int>? _dictionary;
  final _BlockWriter _blocks;

  _Deflater(
    int level,
    this._strategy,
    int windowBits,
    int memLevel,
    this._dictionary,
    this._wrapping,
  ) : _level = level < 0 ? 6 : level,
      _windowBits = windowBits == 8 ? 9 : windowBits,
      _blocks = _BlockWriter(1 << (memLevel + 6)) {
    _blocks.isFixed = _strategy == ZLibOption.strategyFixed;
    // Only zlib streams tell that there is one.
    if (_dictionary case final dictionary? when _wrapping == _Wrapping.zlib) {
      final from = dictionary.length > _size - _leastLeft
          ? dictionary.length - (_size - _leastLeft)
          : 0;
      for (var i = from; i < dictionary.length; i++) {
        _window[_at++] = dictionary[i];
      }
      for (var i = 0; i + 2 < _at; i++) {
        _insert(i);
      }
      _blockStart = _at;
    }
  }

  static const _size = 32768, _shortest = 3, _longest = 258;

  /// What has to be left in the window to look for the longest match.
  static const _leastLeft = _longest + _shortest + 1;

  // For each level, when a match is good enough to look less further, not to
  // look further, and to be taken at once, and how many places are looked at.
  static const _good = [0, 4, 4, 4, 4, 8, 8, 8, 32, 32];
  static const _lazy = [0, 4, 5, 6, 4, 16, 16, 32, 128, 258];
  static const _nice = [0, 8, 16, 32, 16, 32, 128, 128, 258, 258];
  static const _chain = [0, 4, 8, 32, 16, 32, 128, 256, 1024, 4096];

  final Uint8List _window = Uint8List(_size * 2);
  final Int32List _heads = Int32List(1 << 15);
  final Int32List _before = Int32List(_size);

  /// The place in the window, how much there is after it, and where the block
  /// starts. Places in the tables are one higher.
  int _at = 0, _left = 0, _blockStart = 0;

  List<int> _input = const [];
  int _inputAt = 0, _inputEnd = 0, _total = 0;
  final _check = _Check();
  bool _hasHeader = false, _isDone = false;

  /// Whether there is input left.
  bool get hasInput => _inputAt < _inputEnd;

  // What was found one place before, where a match can be longer one place on.
  int _foundLength = 2, _foundAt = 0;
  bool _hasPending = false;

  void add(List<int> data, int start, int end) {
    _input = data;
    _inputAt = start;
    _inputEnd = end;
    _total += end - start;
    switch (_wrapping) {
      case _Wrapping.raw:
        break;
      case _Wrapping.zlib:
        _check.add(data, start, end);
      case _Wrapping.gzip:
        _check.add(data, start, end, isCrc: true);
    }
  }

  /// Compresses what was added. Gives null if there is nothing to take.
  Uint8List? next({required bool flush, required bool end}) {
    if (_isDone) return null;
    if (!_hasHeader) {
      _hasHeader = true;
      _writeHeader();
    }
    if (_level == 0) {
      _store();
    } else {
      _compress(isAll: flush || end);
    }
    if (end) {
      _endBlock(isLast: true);
      _blocks.toByte();
      _writeTrailer();
      _isDone = true;
    } else if (flush && (_wasFed || _at > _blockStart)) {
      _wasFed = false;
      _endBlock();
      _blocks.store(_window, 0, 0, isLast: false);
    }
    return _blocks.take();
  }

  /// Whether there was input since the last flush.
  bool _wasFed = false;

  bool get _isQuick =>
      _strategy == ZLibOption.strategyHuffmanOnly ||
      _strategy == ZLibOption.strategyRle ||
      _strategy == ZLibOption.strategyFixed;

  void _writeHeader() {
    final out = _blocks;
    switch (_wrapping) {
      case _Wrapping.raw:
        break;
      case _Wrapping.zlib:
        final first = 8 | (_windowBits - 8) << 4;
        final kind = _isQuick || _level < 2
            ? 0
            : _level < 6
            ? 1
            : _level == 6
            ? 2
            : 3;
        final dictionary = _dictionary;
        var second = kind << 6 | (dictionary == null ? 0 : 32);
        second += 31 - (first << 8 | second) % 31;
        out
          ..write(first, 8)
          ..write(second, 8);
        if (dictionary != null) {
          final check = _Check()..add(dictionary, 0, dictionary.length);
          out.writeBig(check.adler);
        }
      case _Wrapping.gzip:
        final kind = _level == 9
            ? 2
            : _isQuick || _level < 2
            ? 4
            : 0;
        out
          ..write(0x8b1f, 16)
          ..write(8, 16)
          ..write(0, 32)
          ..write(kind, 8)
          ..write(Platform.isMacOS ? 19 : 3, 8);
    }
  }

  void _writeTrailer() {
    switch (_wrapping) {
      case _Wrapping.raw:
        break;
      case _Wrapping.zlib:
        _blocks.writeBig(_check.adler);
      case _Wrapping.gzip:
        _blocks
          ..write(_check.crc, 32)
          ..write(_total & 0xffffffff, 32);
    }
  }

  /// Moves input into the window.
  void _fill() {
    if (_at >= _size * 2 - _leastLeft) {
      _window.setRange(0, _size, _window, _size);
      _at -= _size;
      _blockStart -= _size;
      _foundAt -= _size;
      for (final table in [_heads, _before]) {
        for (var i = 0; i < table.length; i++) {
          final place = table[i] - _size;
          table[i] = place > 0 ? place : 0;
        }
      }
    }
    final room = _window.length - _at - _left, given = _inputEnd - _inputAt;
    final count = room < given ? room : given;
    if (count == 0) return;
    _wasFed = true;
    _window.setRange(_at + _left, _at + _left + count, _input, _inputAt);
    _inputAt += count;
    _left += count;
  }

  /// Makes blocks of the input as it is.
  void _store() {
    while (true) {
      _fill();
      if (_left == 0) return;
      _at += _left;
      _left = 0;
      if (_at - _blockStart >= _size - 1) _endBlock();
    }
  }

  void _endBlock({bool isLast = false}) {
    final start = _blockStart;
    if (_level == 0) {
      if (_at > start || isLast) {
        _blocks.store(_window, start, _at, isLast: isLast);
      }
    } else if (_blocks.isUsed || isLast) {
      _blocks.end(start < 0 ? null : _window, start, _at, isLast: isLast);
    }
    _blockStart = _at;
  }

  int _hash(int at) =>
      (_window[at] << 10 ^ _window[at + 1] << 5 ^ _window[at + 2]) & 0x7fff;

  /// Notes what is at [at]. Gives the place before where it can be, too.
  int _insert(int at) {
    final hash = _hash(at), before = _heads[hash];
    _before[at & (_size - 1)] = before;
    _heads[hash] = at + 1;
    return before - 1;
  }

  void _compress({required bool isAll}) {
    final isLazy = _level > 3;
    while (true) {
      if (_left < _leastLeft) {
        _fill();
        if (_left < _leastLeft && !isAll && _inputAt == _inputEnd) return;
        if (_left == 0) break;
      }
      if (isLazy) {
        _stepLazily();
      } else {
        _step();
      }
      if (_blocks.isFull) _endBlock();
    }
    if (_hasPending) {
      _blocks.addByte(_window[_at - 1]);
      _hasPending = false;
    }
    _foundLength = 2;
  }

  int get _farthest => (1 << _windowBits) - _leastLeft;

  /// The length of the match at [_at], whose place is in [_matchAt], if it is
  /// longer than [least].
  int _find(int place, int least) {
    switch (_strategy) {
      case ZLibOption.strategyHuffmanOnly:
        return 0;
      case ZLibOption.strategyRle:
        return _findRun();
    }
    final window = _window, at = _at;
    final most = _left < _longest ? _left : _longest;
    var nice = _nice[_level], chain = _chain[_level], best = least;
    if (best >= _good[_level]) chain >>= 2;
    if (nice > most) nice = most;
    var found = 0;
    final limit = at > _farthest ? at - _farthest : -1;
    while (place > limit && place >= 0 && chain-- > 0) {
      if (best >= most) break;
      if (window[place + best] == window[at + best] &&
          window[place] == window[at] &&
          window[place + 1] == window[at + 1]) {
        var length = 2;
        while (length < most && window[place + length] == window[at + length]) {
          length++;
        }
        if (length > best) {
          best = length;
          found = length;
          _matchAt = place;
          if (length >= nice) break;
        }
      }
      final next = _before[place & (_size - 1)] - 1;
      if (next >= place) break;
      place = next;
    }
    return found;
  }

  int _matchAt = 0;

  int _findRun() {
    if (_at == 0) return 0;
    final byte = _window[_at - 1];
    final most = _left < _longest ? _left : _longest;
    var length = 0;
    while (length < most && _window[_at + length] == byte) {
      length++;
    }
    _matchAt = _at - 1;
    return length;
  }

  void _step() {
    final place = _left >= _shortest ? _insert(_at) : -1;
    final length = place >= 0 || _strategy == ZLibOption.strategyRle
        ? _find(place, _shortest - 1)
        : 0;
    if (length < _shortest) {
      _blocks.addByte(_window[_at]);
      _at++;
      _left--;
      return;
    }
    _blocks.addMatch(length, _at - _matchAt);
    _skip(length - 1, notes: length <= _lazy[_level]);
    _at++;
    _left--;
  }

  /// Goes to the last of [count] places.
  void _skip(int count, {bool notes = true}) {
    for (var i = 0; i < count; i++) {
      _at++;
      _left--;
      if (notes && _left >= _shortest) _insert(_at);
    }
  }

  /// Takes a match only if there is no longer one a place on.
  void _stepLazily() {
    final place = _left >= _shortest ? _insert(_at) : -1;
    final before = _foundLength, beforeAt = _foundAt;
    var length = 2;
    if (before < _lazy[_level] &&
        (place >= 0 || _strategy == ZLibOption.strategyRle)) {
      final found = _find(place, before);
      if (found >= _shortest) length = found;
      final isPoor =
          _strategy == ZLibOption.strategyFiltered && length <= 5 ||
          length == _shortest && _at - _matchAt > 4096;
      if (isPoor) length = 2;
    }
    if (before >= _shortest && length <= before) {
      _blocks.addMatch(before, _at - 1 - beforeAt);
      // This place and the one before are noted already.
      _skip(before - 2);
      _hasPending = false;
      _foundLength = 2;
      _at++;
      _left--;
      return;
    }
    if (_hasPending) _blocks.addByte(_window[_at - 1]);
    _hasPending = true;
    _foundLength = length;
    _foundAt = _matchAt;
    _at++;
    _left--;
  }
}
