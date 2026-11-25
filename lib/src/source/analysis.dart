// Only these tell what kind of place a program is in, and can be told about the
// environment.
// ignore_for_file: implementation_imports
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart'
    show AnalysisContextCollectionImpl;
import 'package:analyzer/src/dart/analysis/context_locator.dart'
    show locateContextRoots;
import 'package:analyzer/src/workspace/basic.dart' show BasicWorkspace;

import 'problem.dart';
import 'sdk.dart';

/// The libraries of a program, of which the first has its `main`, and those of
/// the SDK that it needs.
typedef ResolvedLibraries = ({
  List<ResolvedLibraryResult> own,
  List<ResolvedLibraryResult> sdk,
});

/// An analyzer, with what it has resolved.
///
/// Programs outside packages share one, so that the SDK is resolved only once.
/// It does not see when files change, and so is for programs whose files it has
/// not read before, and is kept only after programs without errors.
final class Analysis(
  final String _root,
  final SdkSources _sdk, {

  /// The texts of files that are analyzed as others, by their paths.
  final Map<String, String> replaced = const {},
}) {
  /// The one to be shared. Only one is kept, as each has an SDK.
  static Analysis? _kept;

  /// One for the program at [path], which can be that of others. Whoever gets
  /// it has to [keep] or to [close] it.
  factory of(String path, SdkSources sdk) {
    final kept = _kept;
    if (kept == null || kept._sdk != sdk || !_isOutsidePackages(path)) {
      return Analysis(path, sdk);
    }
    _kept = null;
    return kept;
  }

  late final bool _isShareable = replaced.isEmpty && _isOutsidePackages(_root);

  static bool _isOutsidePackages(String path) {
    final roots = locateContextRoots(
      includedPaths: [path],
      resourceProvider: PhysicalResourceProvider.INSTANCE,
    );
    return roots.every(
      (root) => root.packagesFile == null && root.workspace is BasicWorkspace,
    );
  }

  final _files = _Files();
  late final AnalysisContextCollectionImpl _contexts = _start();
  late final AnalysisSession _session = _contexts
      .contextFor(_root)
      .currentSession;

  /// What it has resolved of the SDK, by URIs.
  final _ofSdk = <String, ResolvedLibraryResult>{};

  AnalysisContextCollectionImpl _start() {
    _sdk.install(_files);
    void add(String path, String text) =>
        _files.setOverlay(path, content: text, modificationStamp: 0);
    replaced.forEach(add);
    // Neither comments nor the options of a project hide errors.
    final options = '${io.File(_root).parent.path}/.dartc_options.yaml';
    add(options, 'analyzer:\n  cannot-ignore: [error]\n');
    return AnalysisContextCollectionImpl(
      includedPaths: [_root],
      sdkPath: _sdk.root,
      resourceProvider: _files,
      optionsFile: options,
      declaredVariables: _sdk.environment,
    );
  }

  /// Keeps this for programs that come later, if they can share it.
  Future<void> keep() async {
    if (!_isShareable) return close();
    final before = _kept;
    _kept = this;
    await before?.close();
  }

  Future<void> close() => _contexts.dispose();

  /// Resolves the library at [path], every one it reaches outside the SDK, and
  /// those of the SDK that can be compiled and are reached, with the runtime.
  ///
  /// Gives null if it has read one of the files before this, as that can have
  /// changed since.
  Future<ResolvedLibraries?> resolve(String path) async {
    final round = _files.startRound();
    if (_files.wasRead(path, before: round)) return null;
    final first = await _session.getResolvedLibrary(path);
    if (first is! ResolvedLibraryResult) {
      throw CompileFailure([
        SourceProblem(path, 1, 1, 'Not a library that can be compiled.'),
      ]);
    }
    final own = [first];
    final seen = {first.element};
    for (var i = 0; i < own.length; i++) {
      for (final next in _reachedBy(own[i].element)) {
        if (!next.isInSdk && seen.add(next)) own.add(await _resolve(next));
      }
    }
    for (final unit in own.expand((library) => library.units)) {
      if (_files.wasRead(unit.path, before: round)) return null;
      if (_mentionedIn(unit)
          .any((path) => _files.wasRead(path, before: round))) {
        return null;
      }
    }
    final needed = _neededOfSdk(seen);
    return (
      own: own,
      sdk: [
        for (final uri in _sdk.libraries)
          if (needed.contains(uri) || _sdk.isRuntime(uri))
            _ofSdk[uri] ??= await _resolveOfSdk(uri),
      ],
    );
  }

  /// The files that the directives of [unit] name, which can be no part of the
  /// program as the analyzer takes them to be something else.
  static Iterable<String> _mentionedIn(ResolvedUnitResult unit) sync* {
    for (final directive in unit.unit.directives) {
      if (directive is! UriBasedDirective) continue;
      final named = [
        directive.uri,
        if (directive is NamespaceDirective)
          for (final configuration in directive.configurations)
            configuration.uri,
      ];
      for (final literal in named) {
        final uri = Uri.tryParse(literal.stringValue ?? '');
        // The SDK does not change.
        if (uri == null || uri.isScheme('dart')) continue;
        final path = unit.session.uriConverter.uriToPath(
          unit.uri.resolveUri(uri),
        );
        if (path != null) yield path;
      }
    }
  }

  Future<ResolvedLibraryResult> _resolveOfSdk(String uri) async {
    final found = await _session.getLibraryByUri(uri);
    return found is LibraryElementResult
        ? _resolve(found.element)
        : throw StateError('No library $uri.');
  }

  Future<ResolvedLibraryResult> _resolve(LibraryElement library) async {
    final result = await _session.getResolvedLibraryByElement(library);
    return result is ResolvedLibraryResult
        ? result
        : throw StateError('Unresolved library ${library.uri}.');
  }

  static Iterable<LibraryElement> _reachedBy(LibraryElement library) => [
    for (final fragment in library.fragments) ...fragment.importedLibraries,
    ...library.exportedLibraries,
  ];

  /// The URIs of the libraries of the SDK that [libraries] reach.
  static Set<String> _neededOfSdk(Iterable<LibraryElement> libraries) {
    final pending = [...libraries], seen = {...libraries};
    while (pending.isNotEmpty) {
      for (final next in _reachedBy(pending.removeLast())) {
        if (seen.add(next)) pending.add(next);
      }
    }
    return {
      for (final library in seen)
        if (library.isInSdk) '${library.uri}',
    };
  }
}

/// Files that remember when the analyzer asked for them first.
///
/// It asks for more than programs have, such as for what is imported under
/// other conditions.
final class _Files() extends OverlayResourceProvider {
  this : super(PhysicalResourceProvider.INSTANCE);

  final _firstRounds = <String, int>{};
  int _round = 0;

  int startRound() => ++_round;

  bool wasRead(String path, {required int before}) =>
      (_firstRounds[path] ?? before) < before;

  @override
  File getFile(String path) {
    _firstRounds.putIfAbsent(path, () => _round);
    return super.getFile(path);
  }
}
