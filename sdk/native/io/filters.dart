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
  ) {
    try {
      _validateZLibeLevel(level);
      _validateZLibWindowBits(windowBits);
      _validateZLibMemLevel(memLevel);
      _validateZLibStrategy(strategy);
    } on ArgumentError {
      throw _InternalError('Failed to create ZLibDeflateFilter');
    }
    final deflater = _Deflater(
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
    );
    return _Filter(
      deflater.add,
      (flush, end) => deflater.next(flush: flush, end: end),
    );
  }

  @patch
  static RawZLibFilter _makeZLibInflateFilter(
    bool gzip,
    int windowBits,
    List<int>? dictionary,
    bool raw,
  ) {
    final inflater = _Inflater(
      windowBits,
      dictionary,
      isRaw: raw,
      concatenates: gzip,
    );
    return _Filter(inflater.add, (_, _) => inflater.next());
  }
}

class _InternalError extends Error {
  final String _message;
  _InternalError(this._message);
  String toString() => "InternalError: '$_message'";
}

final class _Filter(
  final void Function(List<int>, int, int) _add,
  final List<int>? Function(bool, bool) _next,
) implements RawZLibFilter {
  bool _needsDrain = false;

  void process(List<int> data, int start, int end) {
    RangeError.checkValidRange(start, end, data.length);
    if (_needsDrain) {
      throw _InternalError('Call to Process while still processing data');
    }
    _add(data, start, end);
    _needsDrain = true;
  }

  List<int>? processed({bool flush = true, bool end = false}) {
    _needsDrain = false;
    final output = _next(flush, end);
    _needsDrain = output != null;
    return output;
  }
}
