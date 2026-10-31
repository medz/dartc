import 'package:dartc/diagnostics.dart';

import 'library.dart';

/// The immutable result of loading an entry point and its library dependencies.
///
/// Dependencies may contain cycles or unresolved targets. Inspect [hasErrors]
/// before passing the graph to subsequent compiler stages.
final class Project({
  /// The resolved entry-point URI.
  required final Uri entry,

  required Map<Uri, Library> libraries,
  required List<Diagnostic> diagnostics,
}) {
  /// The loaded libraries by logical URI, in discovery order.
  final Map<Uri, Library> libraries = Map.unmodifiable(libraries);

  /// The current load's diagnostics, including parsed-unit diagnostics.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);

  /// Whether any loading, lexical or syntactic error was reported.
  bool get hasErrors =>
      diagnostics.any((diagnostic) => diagnostic.severity == .error);
}
