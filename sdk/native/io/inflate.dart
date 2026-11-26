// Decompression, as RFC 1950 to 1952 tell.

/// How a stream starts and ends.
enum _Wrapping { raw, zlib, gzip }

/// Tells that what follows needs more input.
const _needsMore = -1;

/// Decompresses a stream that comes in pieces.
///
/// What takes more than the input that there is starts again when there is more.
final class _Inflater {
  final List<int>? _dictionary;
  final int _windowBits;

  /// Null until the header tells.
  _Wrapping? _wrapping;

  _Inflater(this._windowBits, this._dictionary, {required bool isRaw})
    : _wrapping = isRaw ? _Wrapping.raw : null {
    // Raw streams do not use the dictionary, as officially.
    if (isRaw) _step = _readBlockHeader;
  }

  Uint8List _input = Uint8List(0);
  int _at = 0, _bits = 0, _bitCount = 0;

  /// The output, with up to 32 KB before what was not taken yet, and where that
  /// starts and ends.
  Uint8List _output = Uint8List(1 << 16);
  int _start = 0, _end = 0;

  /// What comes next. Gives whether there was enough input.
  late bool Function() _step = _readHeader;
  bool _isDone = false, _isLast = false;
  _Codes? _lengths, _distances;
  int _rest = 0, _total = 0;
  _Check _check = _Check();

  static const _window = 32768, _largestPiece = 65536;

  /// Whether the input ran out in the middle of something.
  bool _isStarved = false;

  /// Whether there is input left that can be used.
  bool get hasInput => !_isDone && !_isStarved && _at < _input.length;

  void add(List<int> data, int start, int end) {
    final left = _input.length - _at;
    final input = Uint8List(left + end - start);
    input.setRange(0, left, _input, _at);
    input.setRange(left, input.length, data, start);
    _input = input;
    _at = 0;
    _isStarved = false;
  }

  /// Decompresses some of the input. Gives null if there is nothing left.
  Uint8List? next() {
    if (_isWrong) _fail();
    while (!_isDone && _end - _start < _largestPiece) {
      final at = _at, bits = _bits, bitCount = _bitCount;
      if (_step()) continue;
      _at = at;
      _bits = bits;
      _bitCount = bitCount;
      _isStarved = true;
      break;
    }
    if (_start == _end) return null;
    final left = _end - _start;
    final count = left < _largestPiece ? left : _largestPiece;
    final result = _output.sublist(_start, _start + count);
    _start += count;
    return result;
  }

  /// Whether the data was found wrong, which stays so.
  bool _isWrong = false;

  Never _fail() {
    _isWrong = true;
    throw const FormatException('Filter error, bad data');
  }

  /// [count] bits, or [_needsMore].
  int _read(int count) {
    while (_bitCount < count) {
      if (_at == _input.length) return _needsMore;
      _bits |= _input[_at++] << _bitCount;
      _bitCount += 8;
    }
    final result = _bits & ((1 << count) - 1);
    _bits >>= count;
    _bitCount -= count;
    return result;
  }

  void _toByte() {
    _bits >>= _bitCount & 7;
    _bitCount &= ~7;
  }

  bool _readHeader() {
    final first = _read(8), second = _read(8);
    if (second == _needsMore) return false;
    if (first == 0x1f && second == 0x8b) return _readGzipHeader();
    final window = (first >> 4) + 8;
    if ((first << 8 | second) % 31 != 0 || first & 15 != 8) _fail();
    if (window > 15 || window > _windowBits) _fail();
    _wrapping = _Wrapping.zlib;
    if (second & 32 != 0) {
      final id = _readBig();
      if (id == _needsMore) return false;
      final dictionary = _dictionary;
      if (dictionary == null) _fail();
      final check = _Check()..add(dictionary, 0, dictionary.length);
      if (check.adler != id) _fail();
      _useDictionary(dictionary);
    }
    _step = _readBlockHeader;
    return true;
  }

  void _useDictionary(List<int> dictionary) {
    final from = dictionary.length > _window ? dictionary.length - _window : 0;
    for (var i = from; i < dictionary.length; i++) {
      _output[_end++] = dictionary[i];
    }
    _start = _end;
  }

  int _readBig() {
    final high = _read(16), low = _read(16);
    if (low == _needsMore) return _needsMore;
    final value = low << 16 | high;
    return (value & 0xff) << 24 |
        (value & 0xff00) << 8 |
        value >> 8 & 0xff00 |
        value >> 24;
  }

  bool _readGzipHeader() {
    final method = _read(8), flags = _read(8);
    final time = _read(32), others = _read(16);
    if (others == _needsMore || time == _needsMore) return false;
    if (method != 8 || flags & 0xe0 != 0) _fail();
    if (flags & 4 != 0) {
      final length = _read(16);
      for (var i = 0; i < length; i++) {
        if (_read(8) == _needsMore) return false;
      }
      if (length == _needsMore) return false;
    }
    for (final flag in const [8, 16]) {
      if (flags & flag == 0) continue;
      while (true) {
        final byte = _read(8);
        if (byte == _needsMore) return false;
        if (byte == 0) break;
      }
    }
    if (flags & 2 != 0 && _read(16) == _needsMore) return false;
    _wrapping = _Wrapping.gzip;
    _step = _readBlockHeader;
    return true;
  }

  bool _readBlockHeader() {
    if (_isLast) {
      _toByte();
      _step = _readTrailer;
      return true;
    }
    final isLast = _read(1), kind = _read(2);
    if (kind == _needsMore) return false;
    switch (kind) {
      case 0:
        _toByte();
        final length = _read(16), inverted = _read(16);
        if (inverted == _needsMore) return false;
        if (length != ~inverted & 0xffff) _fail();
        _rest = length;
        _step = _copyStored;
      case 1:
        _lengths = _fixedLengths;
        _distances = _fixedDistances;
        _step = _readSymbols;
      case 2:
        if (!_readCodes()) return false;
        _step = _readSymbols;
      default:
        _fail();
    }
    _isLast = isLast == 1;
    return true;
  }

  /// The length of the code of [symbol] that is known.
  static int _fixedLengthOf(int symbol) => symbol < 144
      ? 8
      : symbol < 256
      ? 9
      : symbol < 280
      ? 7
      : 8;

  static final _fixedLengths = _Codes([
    for (var i = 0; i < 288; i++) _fixedLengthOf(i),
  ]);
  static final _fixedDistances = _Codes(List.filled(32, 5));

  static const _order = [
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15, //
  ];

  bool _readCodes() {
    final lengthCount = _read(5), distanceCount = _read(5), count = _read(4);
    if (count == _needsMore) return false;
    final total = lengthCount + distanceCount + 258;
    if (lengthCount > 29 || distanceCount > 29) _fail();
    final own = List.filled(19, 0);
    for (var i = 0; i < count + 4; i++) {
      final length = _read(3);
      if (length == _needsMore) return false;
      own[_order[i]] = length;
    }
    final codes = _Codes(own);
    if (!codes.isComplete) _fail();
    final lengths = <int>[];
    while (lengths.length < total) {
      final symbol = _readSymbol(codes);
      if (symbol == _needsMore) return false;
      if (symbol < 16) {
        lengths.add(symbol);
        continue;
      }
      final extra = _read(
        symbol == 16
            ? 2
            : symbol == 17
            ? 3
            : 7,
      );
      if (extra == _needsMore) return false;
      if (symbol == 16 && lengths.isEmpty) _fail();
      final repeated = symbol == 16 ? lengths.last : 0;
      final times = extra + (symbol == 18 ? 11 : 3);
      if (lengths.length + times > total) _fail();
      for (var i = 0; i < times; i++) {
        lengths.add(repeated);
      }
    }
    if (lengths[256] == 0) _fail();
    _lengths = _Codes(lengths.sublist(0, lengthCount + 257));
    _distances = _Codes(lengths.sublist(lengthCount + 257));
    if (!_lengths!.isUsable || !_distances!.isUsable) _fail();
    return true;
  }

  /// The next symbol of [codes], or [_needsMore].
  int _readSymbol(_Codes codes) {
    while (_bitCount < 15 && _at < _input.length) {
      _bits |= _input[_at++] << _bitCount;
      _bitCount += 8;
    }
    final known = codes.table[_bits & (_Codes.tableSize - 1)];
    if (known != 0) {
      final length = known & 15;
      if (length > _bitCount) return _needsMore;
      _bits >>= length;
      _bitCount -= length;
      return known >> 4;
    }
    var code = 0, first = 0, index = 0;
    for (var length = 1; length <= 15; length++) {
      final bit = _read(1);
      if (bit == _needsMore) return _needsMore;
      code |= bit;
      final count = codes.counts[length];
      if (code - count < first) return codes.symbols[index + code - first];
      index += count;
      first = (first + count) << 1;
      code <<= 1;
    }
    _fail();
  }

  static const _lengthBases = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, //
    59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
  ];
  static const _lengthBits = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, //
    4, 5, 5, 5, 5, 0,
  ];
  static const _distanceBases = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, //
    513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ];

  /// Decompresses one symbol.
  bool _readSymbols() {
    final symbol = _readSymbol(_lengths!);
    if (symbol == _needsMore) return false;
    if (symbol < 256) {
      _room(1);
      _output[_end++] = symbol;
      _took(1);
      return true;
    }
    if (symbol == 256) {
      _step = _readBlockHeader;
      return true;
    }
    if (symbol > 285) _fail();
    final extra = _read(_lengthBits[symbol - 257]);
    if (extra == _needsMore) return false;
    final code = _readSymbol(_distances!);
    if (code == _needsMore) return false;
    if (code > 29) _fail();
    final more = _read(code < 2 ? 0 : (code >> 1) - 1);
    if (more == _needsMore) return false;
    final length = _lengthBases[symbol - 257] + extra;
    final distance = _distanceBases[code] + more;
    if (distance > _end || distance > 1 << _windowBits) _fail();
    _room(length);
    for (var i = 0; i < length; i++) {
      _output[_end] = _output[_end - distance];
      _end++;
    }
    _took(length);
    return true;
  }

  bool _copyStored() {
    var isAny = false;
    while (_rest > 0) {
      final byte = _read(8);
      // What was copied stays.
      if (byte == _needsMore) return isAny;
      isAny = true;
      _room(1);
      _output[_end++] = byte;
      _took(1);
      _rest--;
      if (_end - _start >= _largestPiece) return true;
    }
    _step = _readBlockHeader;
    return true;
  }

  /// Makes room for [count] bytes.
  void _room(int count) {
    if (_end + count <= _output.length) return;
    // What can be referred to stays, and what was not taken.
    final kept = _end - _window < _start ? _end - _window : _start;
    final from = kept < 0 ? 0 : kept;
    var target = _output;
    if (_end - from + count > target.length) {
      target = Uint8List((_end - from + count) * 2);
    }
    target.setRange(0, _end - from, _output, from);
    _output = target;
    _start -= from;
    _end -= from;
  }

  void _took(int count) {
    _total += count;
    if (_wrapping != _Wrapping.raw) {
      _check.add(_output, _end - count, _end, isCrc: _wrapping == .gzip);
    }
  }

  bool _readTrailer() {
    switch (_wrapping!) {
      case _Wrapping.raw:
        break;
      case _Wrapping.zlib:
        final check = _readBig();
        if (check == _needsMore) return false;
        if (check != _check.adler) _fail();
      case _Wrapping.gzip:
        // The check is compared as soon as it is there.
        final check = _read(32);
        if (check == _needsMore) return false;
        if (check != _check.crc) _fail();
        final length = _read(32);
        if (length == _needsMore) return false;
        if (length != _total & 0xffffffff) _fail();
        // Others can follow.
        _check = _Check();
        _total = 0;
        _isLast = false;
        _step = _readHeader;
        return true;
    }
    _isDone = true;
    return true;
  }
}

/// The codes of symbols whose lengths there are.
final class _Codes {
  /// How many codes of each length there are, and the symbols in their order.
  final List<int> counts = List.filled(16, 0);
  final List<int> symbols = [];
  int _left = 1;

  /// For what the next bits can be, a symbol and the length of its code below
  /// that, or 0 if it is longer.
  final Uint16List table = Uint16List(tableSize);
  static const tableBits = 9, tableSize = 1 << tableBits;

  _Codes(List<int> lengths) {
    for (final length in lengths) {
      counts[length]++;
    }
    counts[0] = 0;
    for (var length = 1; length < 16; length++) {
      _left = _left * 2 - counts[length];
      if (_left < 0) return;
    }
    for (var length = 1; length < 16; length++) {
      for (var i = 0; i < lengths.length; i++) {
        if (lengths[i] == length) symbols.add(i);
      }
    }
    final codes = _BlockWriter._codesOf(lengths);
    for (var i = 0; i < lengths.length; i++) {
      final length = lengths[i];
      if (length == 0 || length > tableBits) continue;
      for (var at = codes[i]; at < tableSize; at += 1 << length) {
        table[at] = i << 4 | length;
      }
    }
  }

  bool get isComplete => _left == 0;

  /// Whether it is, or has no more than one code, of one bit.
  bool get isUsable =>
      _left == 0 ||
      _left > 0 && symbols.length <= 1 && counts[1] == symbols.length;
}

/// Checksums of what is added.
final class _Check {
  int _a = 1, _b = 0, _crc = 0xffffffff;

  int get adler => _b << 16 | _a;
  int get crc => _crc ^ 0xffffffff;

  static final _table = [for (var i = 0; i < 256; i++) _entry(i)];

  static int _entry(int byte) {
    for (var i = 0; i < 8; i++) {
      byte = byte & 1 != 0 ? byte >> 1 ^ 0xedb88320 : byte >> 1;
    }
    return byte;
  }

  void add(List<int> data, int start, int end, {bool isCrc = false}) {
    if (isCrc) {
      var crc = _crc;
      final table = _table;
      for (var i = start; i < end; i++) {
        crc = table[(crc ^ data[i]) & 0xff] ^ crc >> 8;
      }
      _crc = crc;
      return;
    }
    var a = _a, b = _b;
    for (var i = start; i < end; i++) {
      a += data[i] & 0xff;
      if (a >= 65521) a -= 65521;
      b += a;
      if (b >= 65521) b -= 65521;
    }
    _a = a;
    _b = b;
  }
}
