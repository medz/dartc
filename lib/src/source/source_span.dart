import 'source_file.dart';

/// A half-open UTF-16 range within one source snapshot.
///
/// Includes [start] and excludes [end]. Empty ranges, including a range at the
/// end of the source, are valid. Throws [RangeError] unless
/// `0 <= start <= end <= source.length`.
///
/// Equality requires the same source snapshot and the same bounds.
final class SourceSpan(
  /// The source snapshot containing this range.
  final SourceFile source,

  /// The inclusive, zero-based UTF-16 offset.
  final int start,

  /// The exclusive, zero-based UTF-16 offset.
  final int end,
) {
  this {
    RangeError.checkValidRange(start, end, source.length);
  }

  /// The number of UTF-16 code units in this range.
  int get length => end - start;

  /// Whether this range contains no code units.
  bool get isEmpty => start == end;

  /// The source text within this range, extracted on access.
  String get text => source.text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is SourceSpan &&
      identical(source, other.source) &&
      start == other.start &&
      end == other.end;

  @override
  int get hashCode => Object.hash(source, start, end);
}
