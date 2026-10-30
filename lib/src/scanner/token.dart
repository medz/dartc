import '../source/source_file.dart';
import '../source/source_span.dart';
import 'token_kind.dart';

/// A token referring to an unchanged range in a source snapshot.
///
/// Throws [RangeError] unless `0 <= start <= end <= source.length`.
/// Empty ranges represent EOF or empty segments between string interpolations.
final class Token(
  /// The lexical kind of this token.
  final TokenKind kind,

  /// The source snapshot containing this token.
  final SourceFile source,

  /// The inclusive, zero-based UTF-16 offset.
  final int start,

  /// The exclusive, zero-based UTF-16 offset.
  final int end,
) {
  this {
    RangeError.checkValidRange(start, end, source.length);
  }

  /// The number of UTF-16 code units in this token.
  int get length => end - start;

  /// The original token text, extracted on access.
  String get lexeme => source.text.substring(start, end);

  /// The source range, constructed on access.
  SourceSpan get span => SourceSpan(source, start, end);
}
