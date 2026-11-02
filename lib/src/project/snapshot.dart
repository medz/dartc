part of 'load.dart';

bool _sameDirectives(LibraryUnit old, LibraryUnit next) {
  if (old.languageVersion != next.languageVersion ||
      old.versionOverride != next.versionOverride ||
      (old.versionMarker == null) != (next.versionMarker == null)) {
    return false;
  }
  final a = _directives(old).iterator, b = _directives(next).iterator;
  var end = 0;
  while (a.moveNext()) {
    if (!b.moveNext() || a.current.text != b.current.text) return false;
    end = b.current.end;
  }
  return !b.moveNext() &&
      !next.diagnostics.any((d) => (d.span?.start ?? 0) < end);
}

final class _Snapshot(
  final Project project,
  final bool validLinks,
  final Map<Uri, (Uri, int)> parts,
  final Map<Uri, List<Uri>> aliases,
) {
  factory _Snapshot.index(Project project, _Snapshot? old, bool validLinks) {
    if (old != null &&
        old.validLinks &&
        validLinks &&
        old.project.libraries.values.every(
          (l) =>
              l.parts.isEmpty && l.uri.scheme != 'package' ||
              project.libraries.containsKey(l.uri),
        ) &&
        project.libraries.values.every((library) {
          final prior = old.project.libraries[library.uri];
          if (identical(prior, library)) return true;
          if (prior == null) {
            return library.uri.scheme != 'package' && library.parts.isEmpty;
          }
          if (prior.parts.length != library.parts.length) return false;
          for (var i = 0; i < library.parts.length; i++) {
            if (prior.parts[i].source.uri != library.parts[i].source.uri) {
              return false;
            }
          }
          return true;
        })) {
      return _Snapshot(project, validLinks, old.parts, old.aliases);
    }
    final parts = <Uri, (Uri, int)>{};
    final aliases = <Uri, List<Uri>>{};
    void alias(LibraryUnit unit) {
      if (unit.source.uri.scheme == 'package') {
        (aliases[unit.location] ??= []).add(unit.source.uri);
      }
    }

    for (final library in project.libraries.values) {
      alias(library.unit);
      for (var i = 0; i < library.parts.length; i++) {
        final part = library.parts[i];
        if (!parts.containsKey(part.source.uri)) {
          parts[part.source.uri] = (library.uri, i);
          alias(part);
        }
      }
    }
    return _Snapshot(project, validLinks, parts, aliases);
  }

  LibraryUnit? unit(Uri uri) {
    if (project.libraries[uri] case final library?) return library.unit;
    if (parts[uri] case (final owner, final index)) {
      return project.libraries[owner]!.parts[index];
    }
    return null;
  }

  List<Uri> filesAt(Uri location) => [
    if (project.libraries.containsKey(location) || parts.containsKey(location))
      location,
    ...?aliases[location],
  ];

  _Snapshot replace(Map<Uri, LibraryUnit> edits) {
    final libraries = Map.of(project.libraries);
    for (final owner in {for (final uri in edits.keys) parts[uri]?.$1 ?? uri}) {
      final old = libraries[owner]!;
      final unit = edits[owner] ?? old.unit;
      var edges = old.dependencies;
      if (!identical(unit, old.unit)) {
        edges = [];
        for (final directive in _directives(unit)) {
          if (directive is ImportDirective || directive is ExportDirective) {
            edges.add(
              LibraryDependency(
                uri: old.dependencies[edges.length].uri,
                directive: directive,
              ),
            );
          }
        }
        if (old.dependencies.lastOrNull?.isImplicit ?? false) {
          edges.add(old.dependencies.last);
        }
      }
      libraries[owner] = Library(
        unit: unit,
        parts: [for (final part in old.parts) edits[part.source.uri] ?? part],
        dependencies: edges,
      );
    }
    final diagnostics =
        project.diagnostics.isEmpty &&
            edits.values.every((u) => u.diagnostics.isEmpty)
        ? const <Diagnostic>[]
        : <Diagnostic>[
            for (final library in libraries.values) ...[
              ...library.unit.diagnostics,
              for (final part in library.parts) ...part.diagnostics,
            ],
          ];
    return _Snapshot(
      loadedProject(project.entry, libraries, diagnostics),
      true,
      parts,
      aliases,
    );
  }
}
