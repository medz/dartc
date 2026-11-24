@patch
class _Namespace {
  // There is one only.
  @patch
  static _Namespace get _namespace => const _OnlyNamespace();

  @patch
  static int get _namespacePointer => 0;
}

class _OnlyNamespace implements _Namespace {
  const _OnlyNamespace();
}

@patch
class FileStat {
  @patch
  static _statSync(_Namespace namespace, String path) {
    final bytes = FileSystemEntity._toUtf8Array(path);
    if (_statPath(dataAddress(bytes), _buffer) < 0) return _failure();
    return Int64List(6)
      ..[_type] = _told(_typeOf(_statMode))
      ..[_changedTime] = _statChanged
      ..[_modifiedTime] = _statModified
      ..[_accessedTime] = _statAccessed
      ..[_mode] = _statMode
      ..[_size] = _statSize;
  }
}

@patch
class FileSystemEntity {
  @patch
  static _getTypeNative(
    _Namespace namespace,
    Uint8List rawPath,
    bool followLinks,
  ) => _typeAt(rawPath, followLinks);

  @patch
  static _identicalNative(_Namespace namespace, String path1, String path2) {
    final bytes1 = _toUtf8Array(path1), bytes2 = _toUtf8Array(path2);
    if (_statLink(dataAddress(bytes1), _buffer) < 0) return _failure();
    final device = _statDevice, number = _statNumber;
    if (_statLink(dataAddress(bytes2), _buffer) < 0) return _failure();
    return device == _statDevice && number == _statNumber;
  }

  @patch
  static _resolveSymbolicLinks(_Namespace namespace, Uint8List path) =>
      _realPath(dataAddress(path), _buffer) == 0
      ? _failure()
      : _textAt(_buffer);
}

/// The path of [name] in the directory at [path].
Uint8List _joined(Uint8List path, Uint8List name) {
  final length = path.length - 1;
  final needsSlash = length > 0 && path[length - 1] != _slash;
  final start = needsSlash ? length + 1 : length;
  final result = Uint8List(start + name.length + 1)
    ..setRange(0, length, path)
    ..setRange(start, start + name.length, name);
  if (needsSlash) result[length] = _slash;
  return result;
}

const _slash = 0x2f, _dot = 0x2e;

/// What [_readDirectory] gives.
const _entryLength = 18, _entryName = 21;

/// The name of the next entry of [directory], if there is another one.
Uint8List? _nextName(int directory) {
  while (true) {
    _setErrno(0);
    final entry = _readDirectory(directory);
    if (entry == 0) return null;
    final name = _bytesAt(entry + _entryName, load16(entry + _entryLength));
    final isOwn =
        name.length == 1 && name[0] == _dot ||
        name.length == 2 && name[0] == _dot && name[1] == _dot;
    if (!isOwn) return name;
  }
}

/// Whether what is at [path] is deleted, with all that is in it.
bool _deleteAll(Uint8List path) {
  final type = _anyTypeAt(path, false);
  if (type == _typeNone) return false;
  if (type != _typeDirectory) return _unlink(dataAddress(path)) == 0;
  final directory = _openDirectory(dataAddress(path));
  if (directory == 0) return false;
  // Names are not read while others are deleted.
  final names = <Uint8List>[];
  for (
    var name = _nextName(directory);
    name != null;
    name = _nextName(directory)
  ) {
    names.add(name);
  }
  _closeDirectory(directory);
  return names.every((name) => _deleteAll(_joined(path, name))) &&
      _removeDirectory(dataAddress(path)) == 0;
}

/// 1 if there is a directory at [path], 0 if not, or an error.
Object _directoryAt(Uint8List path) {
  const unknown = [9, 12, _eAccess, 14, 84];
  final type = _anyTypeAt(path, true);
  if (type == _typeDirectory) return 1;
  if (type != _typeNone) {
    _setErrno(_eNotDirectory);
    return 0;
  }
  return unknown.contains(_errno) ? _failure() : 0;
}

@patch
class _Directory {
  @patch
  static _current(_Namespace namespace) =>
      _currentDirectory(_buffer, _bufferBytes) == 0
      ? _failure()
      : _textAt(_buffer);

  @patch
  static _setCurrent(_Namespace namespace, Uint8List rawPath) =>
      _succeeded(_changeDirectory(dataAddress(rawPath)));

  @patch
  static _createTemp(_Namespace namespace, Uint8List rawPath) {
    final name = Uint8List(rawPath.length + 6)
      ..setRange(0, rawPath.length - 1, rawPath)
      ..fillRange(rawPath.length - 1, rawPath.length + 5, 0x58);
    if (_makeTemporary(dataAddress(name)) == 0) return _failure();
    return utf8.decode(name.sublist(0, name.length - 1), allowMalformed: true);
  }

  @patch
  static String _systemTemp(_Namespace namespace) {
    final path = Platform.environment['TMPDIR'] ?? '/tmp';
    return path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
  }

  @patch
  static _exists(_Namespace namespace, Uint8List rawPath) =>
      _directoryAt(rawPath);

  @patch
  static _create(_Namespace namespace, Uint8List rawPath) {
    if (_makeDirectory(dataAddress(rawPath), 0x1ff) == 0) return true;
    if (_errno == _eExist && _directoryAt(rawPath) == 1) return true;
    return _failure();
  }

  @patch
  static _deleteNative(
    _Namespace namespace,
    Uint8List rawPath,
    bool recursive,
  ) {
    if (recursive) return _deleteAll(rawPath) ? true : _failure();
    final isLink =
        _typeAt(rawPath, false) == _typeLink &&
        _typeAt(rawPath, true) == _typeDirectory;
    final address = dataAddress(rawPath);
    return _succeeded(isLink ? _unlink(address) : _removeDirectory(address));
  }

  @patch
  static _rename(_Namespace namespace, Uint8List rawPath, String newPath) =>
      _directoryAt(rawPath) == 1 ? _renameTo(rawPath, newPath) : _failure();

  @patch
  static void _fillWithDirectoryListing(
    _Namespace namespace,
    List<FileSystemEntity> list,
    Uint8List rawPath,
    bool recursive,
    bool followLinks,
  ) {
    final listing = _Listing(rawPath, recursive, followLinks);
    while (true) {
      final kind = listing.next(), path = listing.path;
      switch (kind) {
        case _AsyncDirectoryLister.listFile:
          list.add(File.fromRawPath(path));
        case _AsyncDirectoryLister.listDirectory:
          list.add(Directory.fromRawPath(path));
        case _AsyncDirectoryLister.listLink:
          list.add(Link.fromRawPath(path));
        case _AsyncDirectoryLister.listError:
          final error = _failure();
          listing.end();
          throw FileSystemException._fromOSError(
            error,
            'Directory listing failed',
            FileSystemEntity._toStringFromUtf8Array(path),
          );
        default:
          return;
      }
    }
  }
}

/// The directories that are being listed, each one in the one before.
class _Listing {
  final bool _isRecursive, _followsLinks;
  final List<_ListedDirectory> _open;

  /// Where the last entry is, without a 0.
  Uint8List path;

  _Listing(Uint8List start, this._isRecursive, this._followsLinks)
    : _open = [_ListedDirectory(start, const [])],
      path = start.sublist(0, start.length - 1);

  /// The kind of the next entry, as [_AsyncDirectoryLister] has it.
  int next() {
    while (_open.isNotEmpty) {
      final last = _open.last;
      final name = last.next();
      if (name == null) {
        _open.removeLast();
        final code = _errno;
        last.close();
        if (code == 0) continue;
        path = last.path.sublist(0, last.path.length - 1);
        _setErrno(code);
        return _AsyncDirectoryLister.listError;
      }
      final place = _joined(last.path, name);
      path = place.sublist(0, place.length - 1);
      var links = last.links;
      var type = _anyTypeAt(place, false);
      if (type == _typeNone) return _AsyncDirectoryLister.listError;
      if (type == _typeLink && _followsLinks) {
        final link = (_statDevice, _statNumber);
        final target = links.contains(link)
            ? _typeLink
            : _anyTypeAt(place, true);
        type = target == _typeNone ? _typeLink : target;
        if (type == _typeDirectory) links = [...links, link];
      }
      if (type == _typeLink) return _AsyncDirectoryLister.listLink;
      if (type != _typeDirectory) return _AsyncDirectoryLister.listFile;
      if (_isRecursive) _open.add(_ListedDirectory(place, links));
      return _AsyncDirectoryLister.listDirectory;
    }
    return _AsyncDirectoryLister.listDone;
  }

  void end() {
    for (final directory in _open) {
      directory.close();
    }
    _open.clear();
  }
}

/// The directory at [path], which the [links] lead to.
class _ListedDirectory {
  final Uint8List path;
  final List<(int, int)> links;
  int _directory = 0;

  _ListedDirectory(this.path, this.links);

  /// The name of the next entry, or null if there is none or an error.
  Uint8List? next() {
    if (_directory == 0) _directory = _openDirectory(dataAddress(path));
    return _directory == 0 ? null : _nextName(_directory);
  }

  void close() {
    if (_directory != 0) _closeDirectory(_directory);
  }
}
