import 'dart:convert';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';

import 'patch.dart';
import 'sdk_files.dart';

/// The standard libraries that programs are compiled with.
///
/// They are the official sources among [files] with the official patches for
/// native programs, then those that are ours. Of these each directory holds the
/// files patching the library it is named after, and directories with those for
/// some [systems] only. The runtime is the library `dart:_heap`.
final class SdkSources(
  final SdkFiles files, {

  /// What the directories are called that are for the system compiled for.
  final List<String> systems = const [],

  /// What programs are told about where they are compiled, besides what they
  /// can import.
  final Map<String, String> declared = const {},
}) {
  /// The libraries that official code for native programs uses inside.
  static const _hidden = ['_compact_hash', '_vm'];

  /// The libraries that need no more than the official patches.
  static const _whole = ['collection', '_http'];

  /// The libraries without the official patches. These would make programs
  /// reach `dart:io`, for what is not supported.
  static const _unpatched = ['developer'];

  /// Where [install] makes the files be found. The analyzer takes them from
  /// there.
  static const _place = '/dartc-sdk';
  String get root => '$_place/std';

  late final Map<String, String> _overlays = _build();

  /// Makes [to] show the libraries as they are compiled.
  void install(OverlayResourceProvider to) =>
      {
        for (final MapEntry(key: path, value: text) in files.entries)
          if (path.startsWith('std/')) '$_place/$path': text,
        ..._overlays,
      }.forEach(
        (path, text) =>
            to.setOverlay(path, content: text, modificationStamp: 0),
      );

  /// The libraries that can be compiled, by their URIs.
  List<String> get libraries => [
    for (final name in _names) 'dart:$name',
    for (final path in _overlays.keys)
      if (path.contains('/_heap/')) 'dart:_heap/${path.split('/').last}',
  ];

  /// Whether the library at [uri], one of [libraries], is part of the runtime.
  bool isRuntime(String uri) => uri.startsWith('dart:_heap/');

  late final Set<String> _names = {
    ..._whole,
    for (final path in files.keys)
      if (path.startsWith('native/')) path.split('/')[1],
  };

  /// What `fromEnvironment` knows.
  late final Map<String, String> environment = {
    for (final name in _names)
      if (!name.startsWith('_')) 'dart.library.$name': 'true',
    'dart.vm.product': 'true',
    ...declared,
  };

  String get _lib => '$root/lib';

  String _read(String path) => files[path.substring(_place.length + 1)]!;

  Map<String, String> _build() {
    final manifest = jsonDecode(_read('$_lib/libraries.json')) as Map;
    final libraries =
        (manifest['vm_common'] as Map)['libraries'] as Map<String, Object?>;
    final result = <String, String>{};
    for (final MapEntry(key: name, value: library) in libraries.entries) {
      if (!_names.contains(name)) continue;
      library as Map<String, Object?>;
      result.addAll(
        _library(
          '$_lib/${library['uri']}',
          [if (!_unpatched.contains(name)) ..._official(library['patches'])],
          {
            for (final path in files.keys)
              if (_isOwn(path, name)) '$_place/$path': files[path]!,
            if (name == 'core') ..._environmentFile,
          },
        ),
      );
    }
    for (final MapEntry(key: path, value: text) in files.entries) {
      if (path.startsWith('heap/') && path.endsWith('.dart')) {
        result['$_lib/_$path'] = text;
      }
    }
    final names = result.keys.where((path) => path.contains('/_heap/'));
    result['$_lib/_heap/heap.dart'] = [
      for (final path in names) "export '${path.split('/').last}';\n",
    ].join();
    result.addAll(_register(libraries));
    return result;
  }

  /// Whether the file at [path] patches the library [name] for [systems].
  bool _isOwn(String path, String name) =>
      path.endsWith('.dart') &&
      switch (path.split('/')) {
        ['native', final library, _] => library == name,
        ['native', final library, final system, _] =>
          library == name && systems.contains(system),
        _ => false,
      };

  Map<String, String> get _environmentFile {
    // What has no other meaning in strings.
    String text(String value) =>
        "'${[for (final unit in value.codeUnits) '\\u${unit.toRadixString(16).padLeft(4, '0')}'].join()}'";
    return {
      '$_place/native/core/environment_values.dart': [
        'const _environment = <String, String>{',
        for (final MapEntry(:key, :value) in environment.entries)
          '  ${text(key)}: ${text(value)},',
        '};\n',
      ].join('\n'),
    };
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
    Map<String, String> own,
  ) {
    final directory = main.substring(0, main.lastIndexOf('/') + 1);
    String relative(String path) => path.startsWith(directory)
        ? path.substring(directory.length)
        : throw StateError('$path is not in $directory.');
    final files = {
      for (final path in [main, ..._partsOf(main)]) relative(path): _read(path),
    };
    final first = patchLibrary(files, relative(main), {
      for (final path in official) path: _read(path),
    }, added: 'official');
    final second = patchLibrary(first, relative(main), own, added: 'native');
    return {
      for (final MapEntry(key: path, value: text) in second.entries)
        '$directory$path': text,
    };
  }

  List<String> _partsOf(String path) {
    final unit = parseString(
      content: _read(path),
      path: path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit;
    return [
      for (final part in unit.directives.whereType<PartDirective>())
        Uri.file(path).resolve(part.uri.stringValue!).toFilePath(),
    ];
  }

  /// Adds the libraries that the analyzer does not know to its list.
  Map<String, String> _register(Map<String, Object?> libraries) {
    final path = '$_lib/_internal/sdk_library_metadata/lib/libraries.dart';
    final text = _read(path);
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
