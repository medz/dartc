import '../source/source_span.dart';
import 'diagnostic_severity.dart';

/// An immutable report of a problem or information for the caller.
///
/// [span] may be absent when no source location is available, such as when a
/// file cannot be loaded. [notes] are copied in their supplied order, without
/// sorting or deduplication. They can refer to other source snapshots.
final class Diagnostic({
  /// The stable identifier assigned by the reporting domain.
  ///
  /// Consumers identify the kind of problem by this code rather than [message].
  required final String code,

  /// The severity assigned to this occurrence.
  required final DiagnosticSeverity severity,

  /// The explanation for this occurrence, preserved as supplied.
  required final String message,

  /// The primary source range, or `null` when no source location is available.
  final SourceSpan? span,

  List<DiagnosticNote> notes = const [],
}) {
  /// Additional explanations with their own source locations.
  ///
  /// The list cannot be modified, and changes to the supplied list do not
  /// affect this diagnostic.
  final List<DiagnosticNote> notes = notes.isEmpty
      ? const []
      : List.unmodifiable(notes);
}

/// Additional context for a diagnostic at a source location.
final class const DiagnosticNote({
  /// The explanation for this source location.
  required final String message,

  /// The source range associated with this explanation.
  required final SourceSpan span,
});
