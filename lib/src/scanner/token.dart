part of 'scanner.dart';

/// A token referring to an unchanged range in a source snapshot.
///
/// Throws [RangeError] unless `0 <= start <= end <= source.length`.
/// Empty ranges represent EOF or empty segments between string interpolations.
final class Token {
  /// The lexical kind of this token.
  final TokenKind kind;

  /// The source snapshot containing this token.
  final SourceFile source;

  final Object _range;

  Token(TokenKind kind, SourceFile source, int start, int end)
    : this._scanned(
        kind,
        source,
        start,
        RangeError.checkValidRange(start, end, source.length),
      );

  Token._scanned(this.kind, this.source, int start, int end)
    : assert(0 <= start && start <= end && end <= source.length),
      // Keep ordinary ranges in one 32-bit word on all Dart backends.
      _range = start <= 0xFFFFFF && end - start <= 0xFF
          ? (start << 8) | (end - start)
          : (start, end);

  /// The inclusive, zero-based UTF-16 offset.
  int get start {
    final range = _range;
    return range is int ? range >>> 8 : (range as (int, int)).$1;
  }

  /// The exclusive, zero-based UTF-16 offset.
  int get end {
    final range = _range;
    return range is int
        ? (range >>> 8) + (range & 0xFF)
        : (range as (int, int)).$2;
  }

  /// The number of UTF-16 code units in this token.
  int get length => end - start;

  /// The original token text, extracted on access.
  String get lexeme => source.text.substring(start, end);

  /// The source range, constructed on access.
  SourceSpan get span => SourceSpan(source, start, end);
}
