import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:isolate';

import 'package:dartc/ast.dart';
import 'package:dartc/diagnostics.dart';
import 'package:dartc/parser.dart';
import 'package:dartc/source.dart';

import '../parser/parser.dart' show reparseCompilationUnit;
import '../scanner/scanner.dart' show scanUnit;
import 'language_version.dart';
import 'library.dart';
import 'packages/configuration.dart';
import 'project.dart';
import 'resolve_uri.dart';
import 'sources/file_source.dart';
import 'uri_literal.dart';

part 'snapshot.dart';
part 'part_loading.dart';

/// Loads library graphs and reuses unchanged parsed source files between loads.
///
/// [load] reads every reachable source. Use [update] when you know which
/// sources changed. Only the most recently started request can replace the
/// retained snapshot. Create a new loader when the package configuration,
/// environment or default language version changes.
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
  _Snapshot? _last;
  int _generation = 0;

  /// Loads [entry], its parts, selected imports and exports, and `dart:core`.
  ///
  /// [entry] must be absolute. Providers receive resolved source locations;
  /// snapshots keep logical URIs, including `package:` and `dart:` identities.
  /// The provider supplies SDK and application sources. Independent reads can
  /// overlap. Each location is read at most once per call, and library and
  /// part order follows the directives regardless of read completion order.
  /// Missing sources and provider exceptions produce diagnostics. Programming
  /// errors from the provider propagate. Each result belongs to this call;
  /// concurrent callers decide which returned result to display or compile.
  Future<Project> load(Uri entry) => _load(entry, null);

  /// Updates [previous] after the sources in [changedSources] have changed.
  ///
  /// Supply every creation, edit and deletion since [previous], using absolute
  /// provider locations or their `package:` URIs. For a rename, include both
  /// locations. Newly reached units and previously failed reads are read again.
  /// If you cannot account for all changes, call [load].
  ///
  /// A snapshot other than this loader's latest result triggers a full load of
  /// its entry. An empty change set reuses the latest error-free snapshot.
  /// Throws [FormatException] for an invalid URI or an unconfigured package
  /// in [changedSources].
  Future<Project> update(
    Project previous, {
    required Iterable<Uri> changedSources,
  }) async {
    Set<Uri>? changed;
    for (final source in changedSources) {
      final uri = resolveSourceUri(source);
      final location = _sourceLocation(uri);
      if (location == null) {
        throw FormatException('No package configuration entry for $uri.', uri);
      }
      (changed ??= {}).add(location);
    }
    if (!identical(_last?.project, previous)) {
      return _load(previous.entry, null);
    }
    if (changed == null && !previous.hasErrors) {
      _generation++;
      return previous;
    }
    return _load(previous.entry, changed ?? const {});
  }

  Future<Project> _load(Uri entry, Set<Uri>? changed) async {
    final uri = resolveSourceUri(entry);
    final generation = ++_generation;
    final last = _last;
    late final load = _Load(this, last, changed);
    if (last != null &&
        last.validLinks &&
        changed != null &&
        changed.length == 1) {
      final location = changed.single;
      final files = last.filesAt(location);
      if (files.isEmpty) return last.project;
      final result = await _read(location);
      final (text, _) = result;
      if (text != null) {
        final edits = <Uri, LibraryUnit>{};
        var sameLinks = true;
        for (final file in files) {
          final old = last.unit(file)!;
          if (old.source.text == text) continue;
          final unit = _parse(file, location, text, old);
          edits[file] = unit;
          if (!_sameDirectives(old, unit)) sameLinks = false;
        }
        if (sameLinks && generation == _generation) {
          if (edits.isEmpty) return last.project;
          final next = last.replace(edits);
          _last = next;
          return next.project;
        }
        load.staged = edits;
      }
      load.texts[location] = result;
    }
    final project = await load.run(uri);
    if (generation == _generation) {
      _last = _Snapshot.index(project, last, !load.linkError);
    }
    return project;
  }

  Future<_Read> _read(Uri location) async {
    try {
      return (await _readSource(location), null);
    } catch (error, stack) {
      return (null, (error, stack));
    }
  }

  LibraryUnit _parse(
    Uri uri,
    Uri location,
    String text,
    LibraryUnit? previous,
  ) {
    final source = SourceFile(uri, text);
    if (previous != null && previous.diagnostics.isEmpty) {
      final syntax = reparseCompilationUnit(
        source,
        previous.tree,
        previous.languageVersion,
      );
      if (syntax != null) {
        final marker = previous.versionMarker;
        return LibraryUnit(
          syntax: syntax,
          location: location,
          languageVersion: previous.languageVersion,
          versionOverride: previous.versionOverride,
          versionMarker: marker == null
              ? null
              : SourceSpan(source, marker.start, marker.end),
        );
      }
    }
    return _parseUnit(source, location, _versionFor(uri));
  }

  LanguageVersion _versionFor(Uri uri) =>
      _packages.packageFor(uri)?.languageVersion ?? _defaultVersion;

  Uri? _sourceLocation(Uri uri) =>
      uri.scheme == 'package' ? _packages.resolve(uri) : uri;

  /// Releases cached files without invalidating previously returned projects.
  ///
  /// Loads already in progress cannot repopulate the cleared cache.
  void clear() {
    _generation++;
    _last = null;
  }
}

Iterable<Directive> _directives(LibraryUnit unit) sync* {
  for (final member in unit.node.members) {
    if (member is Directive) {
      yield member;
    } else if (unit.diagnostics.isEmpty) {
      // Only a recovered unit can have directives after a declaration.
      break;
    }
  }
}

String? _name(DottedName? name) =>
    name?.components.map((part) => part.text).join('.');

final class _Load(
  final ProjectLoader loader,
  final _Snapshot? previous,
  final Set<Uri>? changed,
) {
  Map<Uri, LibraryUnit>? staged;
  late final completeLibraries =
      previous != null && !previous!.project.hasErrors
      ? previous!.project.libraries
      : const <Uri, Library>{};
  late final changedLibraries = {
    if (previous != null)
      for (final location in changed ?? const <Uri>{})
        for (final file in previous!.filesAt(location))
          previous!.parts[file]?.$1 ?? file,
  };
  final units = <Uri, LibraryUnit>{};
  final libraries = <Uri, Library>{};
  final diagnostics = <Diagnostic>[];
  final texts = <Uri, _Read>{};
  final pending = <Uri, Future<_Read>>{};
  Completer<void>? stopPreparing;
  var providerError = false;
  var prepared = false;
  var linkError = false;
  final owners = <Uri, (Uri, PartDirective)>{};
  final contested = <Uri>{};
  final queue = <(Uri, AstNode?)>[];
  final scheduled = <Uri>{};

  Future<Project> run(Uri entry) async {
    scheduled.add(entry);
    queue.add((entry, null));
    for (var index = 0; index < queue.length; index++) {
      final (uri, origin) = queue[index];
      final old = completeLibraries[uri];
      if (changed != null && old != null && !changedLibraries.contains(uri)) {
        retain(old);
        continue;
      }
      final unit = reuse(uri) ?? await read(uri, origin);
      if (unit == null) continue;
      if (previous == null &&
          !prepared &&
          !providerError &&
          const bool.fromEnvironment('dart.library.io') &&
          unit.node.members.length >= 4 &&
          _directives(unit).whereType<PartDirective>().take(4).length == 4) {
        prepared = true;
        stopPreparing = Completer<void>();
        await Future.any([prepareParts(unit), stopPreparing!.future]);
        stopPreparing = null;
      }
      // An error-free snapshot has one target per directive, in source order.
      final retained = identical(old?.unit, unit) ? old : null;
      final directives = _directives(unit);
      final partOf = retained == null
          ? directives.whereType<PartOfDirective>().firstOrNull
          : null;
      if (partOf != null) {
        error(
          'expected_library',
          '$uri is a part, not a library.',
          linkOrigin(origin) ?? partOf,
        );
      }
      final parts = <LibraryUnit>[];
      final dependencies = <LibraryDependency>[];
      final partUris = <Uri>{};
      var partIndex = 0;
      var sameParts = true;
      Iterator<PartDirective>? partReads;
      for (final member in directives) {
        switch (member) {
          case ImportDirective(:final uri, :final configurations) ||
              ExportDirective(:final uri, :final configurations):
            final index = dependencies.length;
            final prior = old != null && index < old.dependencies.length
                ? old.dependencies[index]
                : null;
            if (prior != null &&
                (retained != null || prior.directive?.text == member.text)) {
              dependencies.add(
                retained != null
                    ? prior
                    : LibraryDependency(uri: prior.uri, directive: member),
              );
              schedule(prior.uri, member);
            } else {
              final selected = select(uri, configurations);
              final target = resolve(selected, unit.source.uri);
              if (target == null) continue;
              dependencies.add(
                LibraryDependency(uri: target, directive: member),
              );
              schedule(target, selected);
            }
          case PartDirective():
            if (changed == null && !prepared) {
              final ahead = partReads ??= directives
                  .whereType<PartDirective>()
                  .iterator;
              while (pending.length < _readAhead && ahead.moveNext()) {
                try {
                  prefetch(_resolve(ahead.current.uri, uri));
                } on FormatException {
                  // The consuming directive reports the error in source order.
                }
              }
            }
            final oldPart = retained?.parts[partIndex];
            partIndex++;
            final target = oldPart?.source.uri ?? resolve(member.uri, uri);
            if (target == null) continue;
            if (!partUris.add(target)) {
              error(
                'duplicate_part',
                'A part cannot be included twice.',
                member.uri,
              );
              continue;
            }
            claimPart(target, uri, member);
            final part = reuse(target) ?? await read(target, member.uri);
            if (!identical(part, oldPart)) {
              sameParts = false;
              if (part != null) checkPart(unit, part, member);
            }
            if (part != null) parts.add(part);
          default:
            break;
        }
      }
      if (uri != _coreLibrary &&
          !dependencies.any(
            (edge) => !edge.isExport && edge.uri == _coreLibrary,
          )) {
        dependencies.add(LibraryDependency(uri: _coreLibrary));
        schedule(_coreLibrary, null);
      }
      libraries[uri] = retained != null && sameParts
          ? retained
          : Library(unit: unit, parts: parts, dependencies: dependencies);
    }
    return loadedProject(entry, libraries, diagnostics);
  }

  void schedule(Uri uri, AstNode? origin) {
    if (scheduled.add(uri)) {
      queue.add((uri, origin));
      if (pending.length < _readAhead &&
          (changed == null || previous?.unit(uri) == null)) {
        prefetch(uri);
      }
    }
  }

  static const _readAhead = 8;

  void prefetch(Uri uri) {
    final location = loader._sourceLocation(uri);
    if (location == null ||
        texts.containsKey(location) ||
        pending.containsKey(location)) {
      return;
    }
    readText(location);
  }

  void claimPart(Uri part, Uri library, PartDirective directive) {
    var first = owners[part];
    if ((first, previous?.parts[part]) case (
      null,
      (final prior, final index),
    )) {
      final old = completeLibraries[prior];
      if (old != null && prior != library) {
        if (identical(libraries[prior], old)) {
          first = (
            prior,
            _directives(old.unit).whereType<PartDirective>().elementAt(index),
          );
        } else {
          contested.add(prior);
        }
      }
    }
    if (first != null && first.$1 != library) {
      error(
        'shared_part',
        'A part cannot belong to more than one library.',
        directive.uri,
        notes: [
          DiagnosticNote(message: 'First included here.', span: first.$2.span),
        ],
      );
    } else {
      owners[part] = (library, directive);
    }
  }

  void retain(Library library) {
    final uri = library.uri;
    if (contested.contains(uri)) {
      var i = 0;
      for (final directive in _directives(
        library.unit,
      ).whereType<PartDirective>()) {
        final target = library.parts[i++].source.uri;
        if (owners.containsKey(target)) claimPart(target, uri, directive);
      }
    }
    libraries[uri] = library;
    for (final edge in library.dependencies) {
      schedule(edge.uri, edge.directive);
    }
  }

  AstNode? linkOrigin(AstNode? origin) => switch (origin) {
    ImportDirective(:final uri, :final configurations) ||
    ExportDirective(
      :final uri,
      :final configurations,
    ) => select(uri, configurations),
    _ => origin,
  };

  LibraryUnit? reuse(Uri uri) {
    if (units[uri] case final loaded?) return loaded;
    if (staged?.remove(uri) case final parsed?) return recordUnit(parsed);
    final changes = changed;
    if (changes == null) return null;
    final old = previous?.unit(uri);
    if (old != null && !changes.contains(old.location)) {
      return recordUnit(old);
    }
    return null;
  }

  LibraryUnit recordUnit(LibraryUnit unit) {
    final uri = unit.source.uri;
    units[uri] = unit;
    diagnostics.addAll(unit.diagnostics);
    return unit;
  }

  Future<LibraryUnit?> read(Uri uri, AstNode? origin) async {
    Uri location;
    try {
      final resolved = loader._sourceLocation(uri);
      if (resolved == null) {
        error(
          'unknown_package',
          'No package configuration entry for $uri.',
          linkOrigin(origin),
        );
        return null;
      }
      location = resolved;
    } on FormatException catch (failure) {
      error('invalid_uri', failure.message, linkOrigin(origin));
      return null;
    }
    final (text, failure) = texts[location] ?? await readText(location);
    if (failure case (final cause, final stack)) {
      if (cause is! Exception) Error.throwWithStackTrace(cause, stack);
      error(
        'source_read_failed',
        'Cannot read $location: $cause',
        linkOrigin(origin),
      );
      return null;
    }
    if (text == null) {
      error(
        'source_not_found',
        'Source not found: $location.',
        linkOrigin(origin),
      );
      return null;
    }
    final old = previous?.unit(uri);
    return recordUnit(
      old != null && old.source.text == text
          ? old
          : loader._parse(uri, location, text, old),
    );
  }

  Future<_Read> readText(Uri location) =>
      pending[location] ??= loader._read(location).then((result) {
        pending.remove(location);
        if (result.$2 case (final error, _) when error is! Exception) {
          providerError = true;
          final stop = stopPreparing;
          if (stop != null && !stop.isCompleted) stop.complete();
        }
        return texts[location] = result;
      });

  StringExpression select(
    StringExpression initial,
    List<ConditionalUri> alternatives,
  ) {
    StringExpression? selected;
    for (final alternative in alternatives) {
      try {
        final value = alternative.value == null
            ? 'true'
            : uriLiteral(alternative.value!);
        if (selected == null &&
            (loader._environment[_name(alternative.name)] ?? '') == value) {
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
      return _resolve(expression, from);
    } on FormatException catch (failure) {
      error('invalid_uri', failure.message, expression);
      return null;
    }
  }

  Uri _resolve(StringExpression expression, Uri from) =>
      resolveSourceUri(Uri.parse(uriLiteral(expression)), from: from);

  void checkPart(
    LibraryUnit library,
    LibraryUnit part,
    PartDirective directive,
  ) {
    final directives = _directives(part);
    final clause = directives.whereType<PartOfDirective>().firstOrNull;
    if (clause == null) {
      error(
        'missing_part_of',
        'The included file must contain a part-of directive.',
        directive.uri,
      );
    } else {
      final matches = switch (clause.target) {
        StringExpression target =>
          resolve(target, part.source.uri) == library.source.uri,
        DottedName target =>
          _directives(library)
              .whereType<LibraryDirective>()
              .any((declaration) => _name(declaration.name) == _name(target)),
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
    for (final member in directives) {
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
    linkError = true;
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

final _coreLibrary = Uri.parse('dart:core');

typedef _Read = (String?, (Object, StackTrace)?);

LibraryUnit _parseUnit(
  SourceFile source,
  Uri location,
  LanguageVersion fallback,
) {
  final input = scanUnit(source);
  final override = versionOverride(input);
  final version = override?.$1 ?? fallback;
  return LibraryUnit(
    syntax: parseCompilationUnit(input, languageVersion: version),
    location: location,
    languageVersion: version,
    versionOverride: override?.$1,
    versionMarker: override?.$2,
    versionDiagnostic: override != null && override.$1 == null
        ? Diagnostic(
            code: 'project.invalid_language_version',
            severity: .error,
            message: 'The language version component is out of range.',
            span: override.$2,
          )
        : null,
  );
}
