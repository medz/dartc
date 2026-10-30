/// Maps UTF-16 offsets to one-based line and column numbers.
///
/// LF, CRLF, and CR end lines. The code units of a line ending belong to the
/// preceding line. An empty source has one line; a trailing line ending starts
/// an empty final line. The end-of-source offset is valid.
///
/// Columns count UTF-16 code units, without expanding tabs or combining Unicode
/// characters.
final class LineInfo(String text) {
  /// The length of the indexed source in UTF-16 code units.
  final int length = text.length;

  final List<int> _starts = _lineStarts(text);

  /// The number of lines, including an empty final line after a line ending.
  int get lineCount => _starts.length;

  /// Returns the one-based line and column at [offset].
  ///
  /// Throws [RangeError] when [offset] is outside `0..length`.
  ({int line, int column}) location(int offset) {
    RangeError.checkValueInInterval(offset, 0, length, 'offset');
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_starts[middle] <= offset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final index = low - 1;
    return (line: index + 1, column: offset - _starts[index] + 1);
  }

  /// Returns the UTF-16 offset for a one-based [line] and [column].
  ///
  /// Line-ending code units are valid columns on their preceding line. Only
  /// the final line includes the end-of-source position. Throws [RangeError]
  /// when either coordinate is outside that line's range.
  int offsetOf(int line, int column) {
    RangeError.checkValueInInterval(line, 1, lineCount, 'line');
    final start = _starts[line - 1];
    final columns = line < lineCount
        ? _starts[line] - start
        : length - start + 1;
    RangeError.checkValueInInterval(column, 1, columns, 'column');
    return start + column - 1;
  }
}

List<int> _lineStarts(String text) {
  final starts = <int>[0];
  for (var offset = 0; offset < text.length; offset++) {
    final unit = text.codeUnitAt(offset);
    if (unit == 0x0D) {
      if (offset + 1 < text.length && text.codeUnitAt(offset + 1) == 0x0A) {
        offset++;
      }
      starts.add(offset + 1);
    } else if (unit == 0x0A) {
      starts.add(offset + 1);
    }
  }
  return starts;
}
