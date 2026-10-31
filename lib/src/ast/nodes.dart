import '../source/source_file.dart';
import '../source/source_span.dart';

part 'nodes/access.dart';
part 'nodes/annotations.dart';
part 'nodes/cascades.dart';
part 'nodes/collections.dart';
part 'nodes/control_flow.dart';
part 'nodes/exceptions.dart';
part 'nodes/expressions.dart';
part 'nodes/functions.dart';
part 'nodes/loops.dart';
part 'nodes/operations.dart';
part 'nodes/parameters.dart';
part 'nodes/pattern_collections.dart';
part 'nodes/pattern_operations.dart';
part 'nodes/patterns.dart';
part 'nodes/records.dart';
part 'nodes/shorthands.dart';
part 'nodes/statements.dart';
part 'nodes/strings.dart';
part 'nodes/switches.dart';
part 'nodes/type_annotations.dart';
part 'nodes/variables.dart';

/// An immutable syntax node within one source snapshot.
///
/// Ranges are half-open UTF-16 offsets. Constructors throw [RangeError] for an
/// invalid range and [ArgumentError] when children belong to another snapshot,
/// overlap, occur out of order, or extend outside their parent.
///
/// Empty ranges can represent missing syntax. Grammar validity and the meaning
/// of names belong to the parser and analyzer. Nodes retain identity equality.
sealed class AstNode({
  /// The source snapshot containing this syntax.
  required final SourceFile source,

  /// The inclusive UTF-16 start offset.
  required final int start,

  /// The exclusive UTF-16 end offset.
  required final int end,
}) {
  this {
    RangeError.checkValidRange(start, end, source.length);
  }

  /// The number of UTF-16 code units in this range.
  int get length => end - start;

  /// The source range, created on access.
  SourceSpan get span => SourceSpan(source, start, end);

  /// The original source text in this range, extracted on access.
  String get text => source.text.substring(start, end);

  /// The number of immediate child nodes.
  int get childCount => 0;

  /// Returns the child at [index], in source order.
  ///
  /// Punctuation and comments are not child nodes. Repeated access returns the
  /// same node. Throws [RangeError] unless `0 <= index < childCount`.
  AstNode childAt(int index) =>
      throw RangeError.index(index, this, 'index', null, childCount);
}

/// An identifier or a keyword used in a name position.
///
/// An empty range represents a missing name during error recovery. Whether
/// the spelling is permitted in this position is checked by the parser.
final class Identifier({
  required super.source,
  required super.start,
  required super.end,
}) extends AstNode implements ForInTarget;

List<T> _freeze<T>(List<T> values) =>
    values.isEmpty ? const [] : List.unmodifiable(values);

void _checkChildren(AstNode node) {
  var end = node.start;
  for (var i = 0; i < node.childCount; i++) {
    final child = node.childAt(i);
    if (!identical(child.source, node.source)) {
      throw ArgumentError('Children must belong to the same source snapshot.');
    }
    if (child.start < end || child.end > node.end) {
      throw ArgumentError(
        'Child ranges must be ordered, non-overlapping, and inside their parent.',
      );
    }
    end = child.end;
  }
}
