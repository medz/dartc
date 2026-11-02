import 'dart:collection';

import 'package:dartc/diagnostics.dart';

import 'library.dart';

/// The immutable result of loading an entry point and its library dependencies.
///
/// Dependencies may contain cycles or unresolved targets. Inspect [hasErrors]
/// before passing the graph to subsequent compiler stages.
final class Project {
  /// Creates a snapshot, copying the supplied collections.
  Project({
    required Uri entry,

    required Map<Uri, Library> libraries,
    required List<Diagnostic> diagnostics,
  }) : this._(
         entry,
         Map.unmodifiable(libraries),
         List.unmodifiable(diagnostics),
       );

  Project._(this.entry, this.libraries, this.diagnostics);

  /// The resolved entry-point URI.
  final Uri entry;

  /// The loaded libraries by logical URI, in discovery order.
  final Map<Uri, Library> libraries;

  /// The current load's diagnostics, including parsed-unit diagnostics.
  final List<Diagnostic> diagnostics;

  /// Whether any loading, lexical or syntactic error was reported.
  bool get hasErrors =>
      diagnostics.any((diagnostic) => diagnostic.severity == .error);
}

Project loadedProject(
  Uri entry,
  Map<Uri, Library> libraries,
  List<Diagnostic> diagnostics,
) => Project._(
  entry,
  UnmodifiableMapView(libraries),
  UnmodifiableListView(diagnostics),
);
