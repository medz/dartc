import 'dart:convert';
import 'dart:typed_data';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:dartc/sdk.dart';

/// Mounts immutable compiler sources alongside the user's physical files.
final class SourceFiles(
  final SourceArchive sources,
  final String root, {
  final SourceArchive? extraSources,
}) implements ResourceProvider {
  Iterable<String> get _paths => sources.paths
      .where((path) => path.startsWith('sdk/'))
      .followedBy(
        extraSources?.paths.where((path) => !path.startsWith('sdk/')) ??
            const [],
      );
  SourceArchive? _archive(String name) =>
      name.startsWith('sdk/') ? sources : extraSources;
  final _physical = PhysicalResourceProvider.INSTANCE;
  @override
  final pathContext = PhysicalResourceProvider.INSTANCE.pathContext;

  bool _contains(String path) =>
      pathContext.isWithin(root, path) || path == root;
  String _name(String path) => path == root
      ? ''
      : pathContext
            .relative(path, from: root)
            .replaceAll(pathContext.separator, '/');
  bool _folder(String path) {
    final name = _name(path);
    return _paths.any((file) => name.isEmpty || file.startsWith('$name/'));
  }

  @override
  File getFile(String path) =>
      _contains(path) ? _SourceFile(this, path) : _physical.getFile(path);
  @override
  Folder getFolder(String path) =>
      _contains(path) ? _SourceFolder(this, path) : _physical.getFolder(path);
  @override
  Resource getResource(String path) => !_contains(path)
      ? _physical.getResource(path)
      : _folder(path)
      ? getFolder(path)
      : getFile(path);
  @override
  Link getLink(String path) {
    if (_contains(path)) {
      throw FileSystemException(path, 'Source resources cannot be links.');
    }
    return _physical.getLink(path);
  }

  @override
  Folder? getStateLocation(String pluginId) =>
      _physical.getStateLocation(pluginId);
}

sealed class _SourceResource(
  @override final SourceFiles provider,
  @override final String path,
) implements Resource {
  @override
  Folder get parent => provider.getFolder(provider.pathContext.dirname(path));
  @override
  String get shortName => provider.pathContext.basename(path);
  @override
  bool isOrContains(String path) =>
      this.path == path ||
      this is Folder && provider.pathContext.isWithin(this.path, path);
  @override
  Resource resolveSymbolicLinksSync() => this;
  @override
  Uri toUri() => provider.pathContext.toUri(path);
  @override
  ResourceWatcher watch() => ResourceWatcher(const Stream.empty(), () async {});
  @override
  Never delete() => _readOnly();

  Never _readOnly() =>
      throw FileSystemException(path, 'Compiler sources are read-only.');
}

final class _SourceFile(super.provider, super.path)
    extends _SourceResource
    implements File {
  @override
  bool get exists =>
      provider._archive(provider._name(path))?.contains(provider._name(path)) ==
      true;
  @override
  int get modificationStamp {
    if (!exists) {
      throw PathNotFoundException(path, 'Source file does not exist.');
    }
    return 0;
  }

  @override
  int get lengthSync =>
      provider._archive(provider._name(path))?.length(provider._name(path)) ??
      (throw PathNotFoundException(path, 'Source file does not exist.'));
  @override
  Uint8List readAsBytesSync() {
    if (!exists) {
      throw PathNotFoundException(path, 'Source file does not exist.');
    }
    return provider._archive(provider._name(path))!.read(provider._name(path));
  }

  @override
  String readAsStringSync() => utf8.decode(readAsBytesSync());
  @override
  File copyTo(Folder parentFolder) {
    parentFolder.create();
    return parentFolder.getFile(shortName)..writeAsBytesSync(readAsBytesSync());
  }

  @override
  Never renameSync(String newPath) => _readOnly();
  @override
  Never writeAsBytesSync(List<int> bytes) => _readOnly();
  @override
  Never writeAsStringSync(String content) => _readOnly();
}

final class _SourceFolder(super.provider, super.path)
    extends _SourceResource
    implements Folder {
  @override
  bool get exists => provider._folder(path);
  @override
  bool get isRoot => parent.path == path;
  @override
  String canonicalizePath(String path) => provider.pathContext.normalize(
    provider.pathContext.isAbsolute(path)
        ? path
        : provider.pathContext.join(this.path, path),
  );
  @override
  bool contains(String path) => isOrContains(path);
  @override
  Resource getChild(String relPath) =>
      provider.getResource(canonicalizePath(relPath));
  @override
  File getFile(String relPath) => provider.getFile(canonicalizePath(relPath));
  @override
  Folder getFolder(String relPath) =>
      provider.getFolder(canonicalizePath(relPath));
  @override
  File getChildAssumingFile(String relPath) => getFile(relPath);
  @override
  Folder getChildAssumingFolder(String relPath) => getFolder(relPath);
  @override
  List<Resource> getChildren() {
    if (!exists) {
      throw PathNotFoundException(path, 'Source folder does not exist.');
    }
    final name = provider._name(path);
    final prefix = name.isEmpty ? '' : '$name/';
    return [
      for (final child in {
        for (final file in provider._paths)
          if (file.startsWith(prefix))
            file.substring(prefix.length).split('/').first,
      })
        getChild(child),
    ];
  }

  @override
  Folder copyTo(Folder parentFolder) {
    final copy = parentFolder.getFolder(shortName)..create();
    for (final child in getChildren()) {
      child.copyTo(copy);
    }
    return copy;
  }

  @override
  void create() {
    if (!exists) _readOnly();
  }
}
