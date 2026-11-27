// What compresses and decompresses.

@patch
class RawZLibFilter {
  @patch
  static RawZLibFilter _makeZLibDeflateFilter(
    bool gzip,
    int level,
    int windowBits,
    int memLevel,
    int strategy,
    List<int>? dictionary,
    bool raw,
  ) => _Compressing(
    _Deflater(
      level,
      strategy,
      windowBits,
      memLevel,
      dictionary,
      raw
          ? _Wrapping.raw
          : gzip
          ? _Wrapping.gzip
          : _Wrapping.zlib,
    ),
  );

  @patch
  static RawZLibFilter _makeZLibInflateFilter(
    bool gzip,
    int windowBits,
    List<int>? dictionary,
    bool raw,
  ) => _Decompressing(
    _Inflater(windowBits, dictionary, isRaw: raw, concatenates: gzip),
  );
}

Never _throwUnfinished() =>
    throw _InternalError('Call to Process while still processing data');

class _InternalError extends Error {
  final String _message;
  _InternalError(this._message);
  String toString() => "InternalError: '$_message'";
}

final class _Compressing implements RawZLibFilter {
  final _Deflater _deflater;
  _Compressing(this._deflater);

  void process(List<int> data, int start, int end) {
    RangeError.checkValidRange(start, end, data.length);
    if (_deflater.hasInput) _throwUnfinished();
    _deflater.add(data, start, end);
  }

  List<int>? processed({bool flush = true, bool end = false}) =>
      _deflater.next(flush: flush, end: end);
}

final class _Decompressing implements RawZLibFilter {
  final _Inflater _inflater;
  _Decompressing(this._inflater);

  void process(List<int> data, int start, int end) {
    RangeError.checkValidRange(start, end, data.length);
    if (_inflater.hasInput) _throwUnfinished();
    _inflater.add(data, start, end);
  }

  List<int>? processed({bool flush = true, bool end = false}) =>
      _inflater.next();
}
