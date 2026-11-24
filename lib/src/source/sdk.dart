import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';

import 'patch.dart';

/// The standard libraries that programs are compiled with.
///
/// They are the official sources at [root] with the official patches for
/// native programs, then those at [patches]. There each directory holds the
/// files patching the library it is named after, and directories with those for
/// some [systems] only. The files at [runtime] are the library `dart:_heap`.
final class SdkSources({
  required final String root,
  required final String patches,
  required final String runtime,

  /// What the directories are called that are for the system compiled for.
  final List<String> systems = const [],
}) {
  /// The libraries that official code for native programs uses inside.
  static const _hidden = ['_compact_hash', '_vm'];

  /// The libraries that need no more than the official patches.
  static const _whole = ['collection'];

  late final Map<String, String> _overlays = _build();

  /// Makes [files] show the libraries as they are compiled.
  void install(OverlayResourceProvider files) => _overlays.forEach(
    (path, text) => files.setOverlay(path, content: text, modificationStamp: 0),
  );

  /// The libraries that can be compiled, by their URIs.
  List<String> get libraries => [
    for (final name in _whole) 'dart:$name',
    for (final directory in Directory(
      patches,
    ).listSync().whereType<Directory>())
      'dart:${directory.path.split('/').last}',
    for (final path in _overlays.keys)
      if (path.contains('/_heap/')) 'dart:_heap/${path.split('/').last}',
  ];

  String get _lib => '$root/lib';

  Map<String, String> _build() {
    final manifest = jsonDecode(
      File('$_lib/libraries.json').readAsStringSync(),
    ) as Map<String, Object?>;
    final common = manifest['vm_common'] as Map<String, Object?>;
    final libraries = common['libraries'] as Map<String, Object?>;
    final result = <String, String>{};
    for (final MapEntry(key: name, value: library) in libraries.entries) {
      final directory = Directory('$patches/$name');
      final isOwn = directory.existsSync();
      if (!isOwn && !_whole.contains(name)) continue;
      library as Map<String, Object?>;
      result.addAll(
        _library('$_lib/${library['uri']}', _official(library['patches']), [
          if (isOwn)
            for (final path in [
              directory.path,
              for (final system in systems) '${directory.path}/$system',
            ])
              if (Directory(path) case final own when own.existsSync())
                for (final file in own.listSync().whereType<File>()) file.path,
        ]),
      );
    }
    for (final file in Directory(runtime).listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final name = file.uri.pathSegments.last;
      result['$_lib/_heap/$name'] = file.readAsStringSync();
    }
    final names = result.keys.where((path) => path.contains('/_heap/'));
    result['$_lib/_heap/heap.dart'] = [
      for (final path in names) "export '${path.split('/').last}';\n",
    ].join();
    result.addAll(_register(libraries));
    return result;
  }

  /// The official patches given as one path or as a list, and their parts.
  List<String> _official(Object? given) {
    final paths = switch (given) {
      String() => [given],
      List() => given.cast<String>(),
      _ => const <String>[],
    };
    return [
      for (final path in paths) ...['$_lib/$path', ..._partsOf('$_lib/$path')],
    ];
  }

  Map<String, String> _library(
    String main,
    List<String> official,
    List<String> own,
  ) {
    Map<String, String> read(List<String> paths) => {
      for (final path in paths) path: File(path).readAsStringSync(),
    };
    final directory = main.substring(0, main.lastIndexOf('/') + 1);
    String relative(String path) => path.startsWith(directory)
        ? path.substring(directory.length)
        : throw StateError('$path is not in $directory.');
    final files = {
      for (final MapEntry(key: path, value: text) in read([
        main,
        ..._partsOf(main),
      ]).entries)
        relative(path): text,
    };
    final first = patchLibrary(
      files,
      relative(main),
      read(official),
      added: 'official',
    );
    final second = patchLibrary(
      first,
      relative(main),
      read(own..sort()),
      added: 'native',
    );
    return {
      for (final MapEntry(key: path, value: text) in second.entries)
        '$directory$path': text,
    };
  }

  static List<String> _partsOf(String path) {
    final unit = parseString(
      content: File(path).readAsStringSync(),
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    return [
      for (final part in unit.directives.whereType<PartDirective>())
        File(path).uri.resolve(part.uri.stringValue!).toFilePath(),
    ];
  }

  /// Adds the libraries that the analyzer does not know to its list.
  Map<String, String> _register(Map<String, Object?> libraries) {
    final path = '$_lib/_internal/sdk_library_metadata/lib/libraries.dart';
    final text = File(path).readAsStringSync();
    const start = 'const Map<String, LibraryInfo> libraries = const {';
    final uris = {
      for (final name in _hidden)
        name: (libraries[name] as Map<String, Object?>)['uri'],
      '_heap': '_heap/heap.dart',
    };
    final added = [
      for (final MapEntry(key: name, value: uri) in uris.entries)
        "\n  '$name': const LibraryInfo('$uri', implementation: true, "
            "documented: false, categories: ''),",
    ];
    if (!text.contains(start)) throw FormatException('$path has no list.');
    return {path: text.replaceFirst(start, '$start${added.join()}')};
  }
}
