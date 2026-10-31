import 'package:dartc/ast.dart';
import 'package:dartc/diagnostics.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/scanner.dart';
import 'package:dartc/source.dart';

import 'language_version.dart';
import 'library.dart';
import 'packages/configuration.dart';
import 'project.dart';
import 'resolve_uri.dart';
import 'sources/file_source.dart';
import 'uri_literal.dart';

/// Loads library graphs and reuses unchanged parsed source files between loads.
///
/// Configuration is immutable for the lifetime of a loader. Each load rereads
/// reachable sources; equal text and language versions reuse the same unit and
/// source snapshot. Only the most recently started load can replace the cache.
/// The cache retains files reached by that load, not all previously seen files.
final class ProjectLoader({
  SourceProvider readSource = readFileSource,
  PackageConfiguration packages = const PackageConfiguration.empty(),
  Map<String, String> environment = const {},
  LanguageVersion defaultLanguageVersion = LanguageVersion.current,
}) {
  final SourceProvider _readSource = readSource;
  final PackageConfiguration _packages = packages;
  final Map<String, String> _environment = Map.unmodifiable(environment);
  final LanguageVersion _defaultVersion = defaultLanguageVersion;
  Map<Uri, LibraryUnit> _cache = {};
  int _generation = 0;

  /// Loads [entry], its parts, selected imports and exports, and `dart:core`.
  ///
  /// [entry] must be absolute. Providers receive resolved source locations;
  /// snapshots keep logical URIs, including `package:` and `dart:` identities.
  /// The provider supplies SDK sources as well as application sources.
  /// Missing sources and provider exceptions produce diagnostics. Programming
  /// errors from the provider propagate. Each result belongs to this call;
  /// concurrent callers decide which returned result to display or compile.
  Future<Project> load(Uri entry) async {
    final uri = resolveSourceUri(entry);
    final generation = ++_generation;
    final load = _Load(
      _readSource,
      _packages,
      _environment,
      _defaultVersion,
      _cache,
    );
    final project = await load.run(uri);
    if (generation == _generation) _cache = load.units;
    return project;
  }

  /// Releases cached files without invalidating previously returned projects.
  ///
  /// Loads already in progress cannot repopulate the cleared cache.
  void clear() {
    _generation++;
    _cache = {};
  }
}

final class _Load(
  final SourceProvider readSource,
  final PackageConfiguration packages,
  final Map<String, String> environment,
  final LanguageVersion defaultVersion,
  final Map<Uri, LibraryUnit> previous,
) {
  final units = <Uri, LibraryUnit>{};
  final libraries = <Uri, Library>{};
  final diagnostics = <Diagnostic>[];
  final texts = <Uri, (String?, Exception?)>{};
  final owners = <Uri, (Uri, PartDirective)>{};
  final queue = <(Uri, AstNode?)>[];
  final scheduled = <Uri>{};
  final core = Uri.parse('dart:core');

  Future<Project> run(Uri entry) async {
    schedule(entry, null);
    for (var index = 0; index < queue.length; index++) {
      final (uri, origin) = queue[index];
      final unit = await read(uri, origin);
      if (unit == null) continue;
      final partOf = unit.node.members.whereType<PartOfDirective>().firstOrNull;
      if (partOf != null) {
        error(
          'expected_library',
          '$uri is a part, not a library.',
          origin ?? partOf,
        );
      }
      final parts = <LibraryUnit>[];
      final dependencies = <LibraryDependency>[];
      final partUris = <Uri>{};
      for (final member in unit.node.members) {
        switch (member) {
          case ImportDirective(:final uri, :final configurations) ||
              ExportDirective(:final uri, :final configurations):
            final selected = select(uri, configurations);
            if (selected == null) continue;
            final target = resolve(selected, unit.source.uri);
            if (target == null) continue;
            dependencies.add(
              LibraryDependency(uri: target, directive: member as Directive),
            );
            schedule(target, selected);
          case PartDirective():
            final target = resolve(member.uri, uri);
            if (target == null) continue;
            if (!partUris.add(target)) {
              error(
                'duplicate_part',
                'A part cannot be included twice.',
                member.uri,
              );
              continue;
            }
            if (owners[target] case final owner? when owner.$1 != uri) {
              error(
                'shared_part',
                'A part cannot belong to more than one library.',
                member.uri,
                notes: [
                  DiagnosticNote(
                    message: 'First included here.',
                    span: owner.$2.span,
                  ),
                ],
              );
            } else {
              owners[target] = (uri, member);
            }
            final part = await read(target, member.uri);
            if (part == null) continue;
            checkPart(unit, part, member);
            parts.add(part);
          default:
            break;
        }
      }
      if (uri != core &&
          !dependencies.any((edge) => !edge.isExport && edge.uri == core)) {
        dependencies.add(LibraryDependency(uri: core));
        schedule(core, null);
      }
      libraries[uri] = Library(
        unit: unit,
        parts: parts,
        dependencies: dependencies,
      );
    }
    return Project(
      entry: entry,
      libraries: libraries,
      diagnostics: diagnostics,
    );
  }

  void schedule(Uri uri, AstNode? origin) {
    if (scheduled.add(uri)) queue.add((uri, origin));
  }

  Future<LibraryUnit?> read(Uri uri, AstNode? origin) async {
    Uri location;
    try {
      final resolved = uri.scheme == 'package' ? packages.resolve(uri) : uri;
      if (resolved == null) {
        error(
          'unknown_package',
          'No package configuration entry for $uri.',
          origin,
        );
        return null;
      }
      location = resolved;
    } on FormatException catch (failure) {
      error('invalid_uri', failure.message, origin);
      return null;
    }
    if (!texts.containsKey(location)) {
      try {
        texts[location] = (await readSource(location), null);
      } on Exception catch (failure) {
        texts[location] = (null, failure);
      }
    }
    final (text, failure) = texts[location]!;
    if (failure != null) {
      error('source_read_failed', 'Cannot read $location: $failure', origin);
      return null;
    }
    if (text == null) {
      error('source_not_found', 'Source not found: $location.', origin);
      return null;
    }
    final fallback =
        packages.packageFor(uri)?.languageVersion ?? defaultVersion;
    final old = units[uri] ?? previous[uri];
    if (old != null &&
        old.source.text == text &&
        old.languageVersion == (old.versionOverride ?? fallback)) {
      if (!units.containsKey(uri)) diagnostics.addAll(old.diagnostics);
      units[uri] = old;
      return old;
    }
    final source = old != null && old.source.text == text
        ? old.source
        : SourceFile(uri, text);
    final input = scan(source);
    final override = versionOverride(input);
    final version = override?.$1 ?? fallback;
    final result = parseCompilationUnit(input, languageVersion: version);
    final unit = LibraryUnit(
      node: result.node,
      languageVersion: version,
      versionOverride: override?.$1,
      versionMarker: override?.$2,
      diagnostics: override != null && override.$1 == null
          ? [
              Diagnostic(
                code: 'project.invalid_language_version',
                severity: .error,
                message: 'The language version component is out of range.',
                span: override.$2,
              ),
              ...result.diagnostics,
            ]
          : result.diagnostics,
    );
    units[uri] = unit;
    diagnostics.addAll(unit.diagnostics);
    return unit;
  }

  StringExpression? select(
    StringExpression initial,
    List<ConditionalUri> alternatives,
  ) {
    StringExpression? selected;
    for (final alternative in alternatives) {
      final name = alternative.name.components
          .map((part) => part.text)
          .join('.');
      try {
        final value = alternative.value == null
            ? 'true'
            : uriLiteral(alternative.value!);
        if (selected == null && (environment[name] ?? '') == value) {
          selected = alternative.uri;
        }
      } on FormatException catch (failure) {
        error('invalid_configuration', failure.message, alternative);
      }
    }
    return selected ?? initial;
  }

  Uri? resolve(StringExpression expression, Uri from) {
    try {
      return resolveSourceUri(Uri.parse(uriLiteral(expression)), from: from);
    } on FormatException catch (failure) {
      error('invalid_uri', failure.message, expression);
      return null;
    }
  }

  void checkPart(
    LibraryUnit library,
    LibraryUnit part,
    PartDirective directive,
  ) {
    final clauses = part.node.members.whereType<PartOfDirective>().toList();
    if (clauses.isEmpty) {
      error(
        'missing_part_of',
        'The included file must contain a part-of directive.',
        directive.uri,
      );
    } else {
      final clause = clauses.first;
      final matches = switch (clause.target) {
        StringExpression target =>
          resolve(target, part.source.uri) == library.source.uri,
        DottedName target =>
          library.node.members.whereType<LibraryDirective>().any(
            (declaration) =>
                declaration.name?.components
                    .map((name) => name.text)
                    .join('.') ==
                target.components.map((name) => name.text).join('.'),
          ),
      };
      if (!matches) {
        error(
          'part_of_mismatch',
          'The part-of directive does not identify ${library.source.uri}.',
          clause,
          notes: [
            DiagnosticNote(message: 'Included here.', span: directive.uri.span),
          ],
        );
      }
    }
    for (final member in part.node.members.whereType<Directive>()) {
      if (member is! PartOfDirective) {
        error(
          'directive_in_part',
          'A part cannot contain library, import, export or part directives.',
          member,
        );
      }
    }
    if ((library.versionMarker == null) != (part.versionMarker == null) ||
        library.versionOverride != part.versionOverride ||
        library.languageVersion != part.languageVersion) {
      error(
        'part_language_version',
        'The library and its parts must have the same language version and explicit override.',
        directive.uri,
        notes: [
          if (library.versionMarker case final span?)
            DiagnosticNote(message: 'Library version override.', span: span),
          if (part.versionMarker case final span?)
            DiagnosticNote(message: 'Part version override.', span: span),
        ],
      );
    }
  }

  void error(
    String code,
    String message,
    AstNode? node, {
    List<DiagnosticNote> notes = const [],
  }) {
    diagnostics.add(
      Diagnostic(
        code: 'project.$code',
        severity: .error,
        message: message,
        span: node?.span,
        notes: notes,
      ),
    );
  }
}
