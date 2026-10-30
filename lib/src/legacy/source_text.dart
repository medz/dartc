// The decoded input used by scanning, parsing and diagnostics. Offsets are UTF-16.
class SourceText {
  final String path;
  final String text;

  SourceText(this.path, this.text);
}
