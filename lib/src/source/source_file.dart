import 'line_info.dart';

/// An immutable snapshot of source text identified by a URI.
///
/// The URI and text are preserved as supplied. URI resolution and text decoding
/// belong to the caller. Separate snapshots have distinct identities, even when
/// they have the same URI and text.
final class SourceFile(
  /// The caller-supplied URI of this source.
  final Uri uri,

  /// The decoded source text, without newline or Unicode normalization.
  final String text,
) {
  /// The number of UTF-16 code units in [text].
  int get length => text.length;

  /// The line index, built once on first access.
  late final LineInfo lineInfo = LineInfo(text);
}
