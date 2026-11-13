import '../runtime/decimal.dart';

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
