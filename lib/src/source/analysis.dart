import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
// Only this can be told about the environment.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart'
    show AnalysisContextCollectionImpl;

import 'problem.dart';
import 'sdk.dart';

/// The libraries of a program, of which the first has its `main`, and those of
/// the SDK that it needs.
typedef ResolvedLibraries = ({
  List<ResolvedLibraryResult> own,
  List<ResolvedLibraryResult> sdk,
});

/// An analyzer, with what it has resolved.
final class Analysis(
  final String _root,
  final SdkSources _sdk, {

  /// The texts of files that are analyzed as others, by their paths.
  final Map<String, String> replaced = const {},

  /// Whether other programs can use it.
  final bool isShareable = false,
}) {
  /// The last one that was shared. Others are not kept, as each has an SDK.
  static Analysis? _shared;

  /// One that programs outside packages have in common, so that the SDK is
  /// resolved only once. Others have their own.
  ///
  /// Whoever gets it has to [release] it, and to [share] it again if there were
  /// no errors, and no files that were read before, as it does not see when
  /// files change.
  factory shared(String path, SdkSources sdk) {
    for (var at = File(path).parent; ; at = at.parent) {
      final isPackage = [
        '.dart_tool/package_config.json',
        'pubspec.yaml',
      ].any((name) => File('${at.path}/$name').existsSync());
      if (isPackage) return Analysis(path, sdk);
      if (at.path == at.parent.path) break;
    }
    final shared = _shared;
    return shared != null && shared._sdk == sdk
        ? shared
        : Analysis(path, sdk, isShareable: true);
  }

  /// The files outside the SDK that it has read.
  final _read = <String>{};

  /// What it has resolved of the SDK, by URIs.
  final _ofSdk = <String, ResolvedLibraryResult>{};
  late final AnalysisSession _session = _start();

  AnalysisSession _start() {
    final files = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    _sdk.install(files);
    void add(String path, String text) =>
        files.setOverlay(path, content: text, modificationStamp: 0);
    replaced.forEach(add);
    // Neither comments nor the options of a project hide errors.
    final options = '${File(_root).parent.path}/.dartc_options.yaml';
    add(options, 'analyzer:\n  cannot-ignore: [error]\n');
    final contexts = AnalysisContextCollectionImpl(
      includedPaths: [_root],
      sdkPath: _sdk.root,
      resourceProvider: files,
      optionsFile: options,
      declaredVariables: _sdk.environment,
    );
    return contexts.contextFor(_root).currentSession;
  }

  /// Shares this with programs that come later, if it can be, or not any longer.
  void share() {
    if (isShareable) _shared = this;
  }

  void release() {
    if (_shared == this) _shared = null;
  }

  /// Notes that the files of [libraries] were read. Gives whether this was the
  /// first time for all. If not, some can have changed since.
  bool isFirstToRead(List<ResolvedLibraryResult> libraries) => {
    for (final library in libraries)
      for (final unit in library.units) unit.path,
  }.map(_read.add).toList().every((isNew) => isNew);

  /// Resolves the library at [path], every one it reaches outside the SDK, and
  /// those of the SDK that can be compiled and are reached, with the runtime.
  Future<ResolvedLibraries> resolve(String path) async {
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
