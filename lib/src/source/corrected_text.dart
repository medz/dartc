/// Another text for a part of a file.
typedef Edit = ({int offset, int end, String text});

/// The text of a file that the analyzer is given in place of [original], so
/// that it evaluates constants as the official compiler does.
final class CorrectedText(
  final String original,
  final List<Edit> _edits, {
  final Map<String, String> enumNameFields = const {},
}) {
  late final String text = () {
    final result = StringBuffer();
    var at = 0;
    for (final (:offset, :end, :text) in _edits) {
      result
        ..write(original.substring(at, offset))
        ..write(text);
      at = end;
    }
    return '$result${original.substring(at)}';
  }();

  /// Where in [original] is what is at [offset] of [text], or where the edit
  /// that made it starts.
  int originalOffset(int offset) {
    var shift = 0;
    for (final edit in _edits) {
      final start = edit.offset + shift;
      if (offset < start) break;
      if (offset < start + edit.text.length) return edit.offset;
      shift += edit.text.length - (edit.end - edit.offset);
    }
    return offset - shift;
  }
}
