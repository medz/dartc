import 'decimal.dart';

@patch
double _parseDouble(String source, int start, int end) =>
    DoubleText.tryParse(source, start, end)!;

@patch
class _JsonStringDecoderSink {
  @patch
  @pragma(
    'dartc:patch',
    'specification: the final JSON slice delivers its value and closes the output sink',
  )
  void addSlice(String chunk, int start, int end, bool isLast) {
    _parser.chunk = chunk;
    _parser.chunkEnd = end;
    _parser.parse(start);
    // The final slice must also deliver the value and close the output sink.
    if (isLast) close();
  }
}

@patch
class _Base64DecoderSink {
  @patch
  @pragma(
    'dartc:patch',
    'specification: an empty final Base64 slice validates pending data and closes the output sink',
  )
  void addSlice(String string, int start, int end, bool isLast) {
    RangeError.checkValidRange(start, end, string.length);
    if (start != end) {
      final buffer = _decoder.decode(string, start, end);
      if (buffer != null) _sink.add(buffer);
    }
    if (isLast) {
      _decoder.close(string, end);
      _sink.close();
    }
  }
}

@patch
class _Latin1DecoderSink {
  @patch
  @pragma(
    'dartc:patch',
    'specification: an empty final Latin-1 slice closes its output sink',
  )
  void addSlice(List<int> source, int start, int end, bool isLast) {
    RangeError.checkValidRange(start, end, source.length);
    if (start == end) {
      if (isLast) close();
      return;
    }
    if (source is! Uint8List) _checkValidLatin1(source, start, end);
    _addSliceToSink(source, start, end, isLast);
  }
}

@patch
class _Latin1AllowInvalidDecoderSink {
  @patch
  @pragma(
    'dartc:patch',
    'specification: the final replacement-mode Latin-1 slice closes its output exactly once',
  )
  void addSlice(List<int> source, int start, int end, bool isLast) {
    RangeError.checkValidRange(start, end, source.length);
    for (var i = start; i < end; i++) {
      final char = source[i];
      if (char > _latin1Mask || char < 0) {
        if (i > start) _addSliceToSink(source, start, i, false);
        _addSliceToSink(const [0xFFFD], 0, 1, false);
        start = i + 1;
      }
    }
    if (start < end) _addSliceToSink(source, start, end, false);
    if (isLast) close();
  }
}
