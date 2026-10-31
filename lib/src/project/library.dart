import 'package:dartc/ast.dart';
import 'package:dartc/diagnostics.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/source.dart';

/// A parsed file with its selected language version and source snapshot.
final class LibraryUnit({
  /// The immutable syntax tree and its source snapshot.
  required final CompilationUnit node,

  /// The language version used to parse this file.
  required final LanguageVersion languageVersion,

  /// The first file version override, or `null` when absent or malformed.
  final LanguageVersion? versionOverride,

  /// The version comment, including a malformed version reported in diagnostics.
  final SourceSpan? versionMarker,

  required List<Diagnostic> diagnostics,
}) {
  /// The lexical, syntactic and file-version diagnostics, in discovery order.
  final List<Diagnostic> diagnostics = List.unmodifiable(diagnostics);

  /// The source snapshot shared by all nodes in this file.
  SourceFile get source => node.source;
}

/// A selected import or export edge, before namespace resolution.
final class LibraryDependency({
  /// The resolved logical URI of the target library.
  required final Uri uri,

  /// The written import or export, or `null` for the implicit `dart:core` import.
  final Directive? directive,
}) {
  this {
    if (directive != null &&
        directive is! ImportDirective &&
        directive is! ExportDirective) {
      throw ArgumentError.value(
        directive,
        'directive',
        'Expected an import or export.',
      );
    }
  }

  /// Whether this edge contributes an exported namespace.
  bool get isExport => directive is ExportDirective;

  /// Whether this edge is an implicit core import.
  bool get isImplicit => directive == null;
}

/// A library's defining unit, ordered parts and selected dependencies.
final class Library({
  /// The unit containing this library's directives and declarations.
  required final LibraryUnit unit,

  List<LibraryUnit> parts = const [],
  List<LibraryDependency> dependencies = const [],
}) {
  /// The included parts, in directive order.
  final List<LibraryUnit> parts = List.unmodifiable(parts);

  /// The import and export edges, including any implicit core import.
  final List<LibraryDependency> dependencies = List.unmodifiable(dependencies);

  /// The canonical logical source URI of this library.
  Uri get uri => unit.source.uri;
}
