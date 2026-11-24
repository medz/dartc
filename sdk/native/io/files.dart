const _readOnly = 0, _writeOnly = 1, _readWrite = 2;
const _createFlag = 0x200, _truncateFlag = 0x400, _exclusiveFlag = 0x800;
const _closeOnExec = 0x1000000;
const _fromStart = 0, _fromCurrent = 1, _fromEnd = 2;
const _allOfFile = 15;

/// Opens the file at [path]. Returns a negative number if it cannot.
int _openFileAt(Uint8List path, int flags) {
  final file = _openPath(dataAddress(path), flags | _closeOnExec, 0x1b6);
  if (file < 0) return file;
  if (_statFile(file, _buffer) == 0 && _typeOf(_statMode) != _typeDirectory) {
    return file;
  }
  _closeFile(file);
  _setErrno(_eIsDirectory);
  return -1;
}

/// The last error if [result] is negative and else true.
Object _succeeded(int result) => _valueIf(result, true);

/// Does [work] with [path] if that is a file, or else says why not.
Object? _withFile(Uint8List path, Object? Function() work) =>
    _withType(_typeAt(path, true), work);

Object? _withType(int type, Object? Function() work) => switch (type) {
  _typeDirectory => _failure(_eIsDirectory),
  _typeNone => _failure(_eNoEnt),
  _ => work(),
};

/// What [result] gives after finding out about the file at [path].
Object? _fact(Uint8List path, int Function() result) =>
    _withType(_anyTypeAt(path, true), result);

/// Does [work] with [path] if that is a link, or else says why not.
Object? _withLink(Uint8List path, Object? Function() work) =>
    switch (_typeAt(path, false)) {
      _typeLink => work(),
      _typeDirectory => _failure(_eIsDirectory),
      _typeNone => _failure(_eNoEnt),
      _ => _failure(_eInvalid),
    };

Object? _renameTo(Uint8List path, String to) {
  final target = FileSystemEntity._toUtf8Array(to);
  return _succeeded(_renamePath(dataAddress(path), dataAddress(target)));
}

/// Sets the times of the file at [path] to [accessed] and [modified].
Object? _changeTimes(Uint8List path, int accessed, int modified) {
  for (final (i, time) in [accessed, modified].indexed) {
    // The microseconds are never negative.
    store64(_buffer + i * 16, (time - time % 1000000) ~/ 1000000);
    store64(_buffer + i * 16 + 8, time % 1000000);
  }
  return _succeeded(_setTimes(dataAddress(path), _buffer));
}

@patch
class _File {
  @patch
  static _exists(_Namespace namespace, Uint8List rawPath) {
    final type = _anyTypeAt(rawPath, true);
    return type != _typeNone && type != _typeDirectory;
  }

  @patch
  static _create(_Namespace namespace, Uint8List rawPath, bool exclusive) {
    final flags = _createFlag | (exclusive ? _exclusiveFlag : 0);
    final file = _openFileAt(rawPath, flags);
    if (file < 0) return _failure();
    _closeFile(file);
    return true;
  }

  @patch
  static _createLink(_Namespace namespace, Uint8List rawPath, String target) {
    final text = FileSystemEntity._toUtf8Array(target);
    return _succeeded(_makeLink(dataAddress(text), dataAddress(rawPath)));
  }

  @patch
  static List<dynamic> _createPipe(_Namespace namespace) {
    if (_makePipe(_buffer) < 0) throw _failure();
    return [load32(_buffer) + 1, load32(_buffer + 4) + 1];
  }

  @patch
  static _linkTarget(_Namespace namespace, Uint8List rawPath) {
    if (_typeAt(rawPath, false) != _typeLink) return _failure(_eNoEnt);
    final length = _readLink(dataAddress(rawPath), _buffer, _bufferBytes);
    if (length < 0) return _failure();
    return utf8.decode(_bytesAt(_buffer, length), allowMalformed: true);
  }

  @patch
  static _deleteNative(_Namespace namespace, Uint8List rawPath) =>
      _withFile(rawPath, () => _succeeded(_unlink(dataAddress(rawPath))));

  @patch
  static _deleteLinkNative(_Namespace namespace, Uint8List rawPath) =>
      _withLink(rawPath, () => _succeeded(_unlink(dataAddress(rawPath))));

  @patch
  static _rename(_Namespace namespace, Uint8List oldPath, String newPath) =>
      _withFile(oldPath, () => _renameTo(oldPath, newPath));

  @patch
  static _renameLink(_Namespace namespace, Uint8List oldPath, String newPath) =>
      _withLink(oldPath, () => _renameTo(oldPath, newPath));

  @patch
  static _copy(_Namespace namespace, Uint8List oldPath, String newPath) =>
      _withFile(oldPath, () {
        final target = FileSystemEntity._toUtf8Array(newPath);
        return _succeeded(
          _copyFile(dataAddress(oldPath), dataAddress(target), 0, _allOfFile),
        );
      });

  @patch
  static _lengthFromPath(_Namespace namespace, Uint8List rawPath) =>
      _fact(rawPath, () => _statSize);

  @patch
  static _lastModified(_Namespace namespace, Uint8List rawPath) =>
      _fact(rawPath, () => _statModified);

  @patch
  static _setLastModified(
    _Namespace namespace,
    Uint8List rawPath,
    int micros,
  ) => _withFile(rawPath, () => _changeTimes(rawPath, _statAccessed, micros));

  @patch
  static _lastAccessed(_Namespace namespace, Uint8List rawPath) =>
      _fact(rawPath, () => _statAccessed);

  @patch
  static _setLastAccessed(
    _Namespace namespace,
    Uint8List rawPath,
    int micros,
  ) => _withFile(rawPath, () => _changeTimes(rawPath, micros, _statModified));

  @patch
  static _open(_Namespace namespace, Uint8List rawPath, int mode) {
    final flags = switch (mode) {
      0 => _readOnly,
      1 => _readWrite | _createFlag | _truncateFlag,
      2 => _readWrite | _createFlag,
      3 => _writeOnly | _createFlag | _truncateFlag,
      _ => _writeOnly | _createFlag,
    };
    final file = _openFileAt(rawPath, flags);
    if (file < 0) return _failure();
    if (mode == 2 || mode == 4) _seekFile(file, 0, _fromEnd);
    return file + 1;
  }

  @patch
  static int _openStdio(int fd) => fd + 1;
}

@patch
class _RandomAccessFile {
  // There is no debugger to tell about it.
  @patch
  void _maybeConnectHandler() {}
}

@patch
class _RandomAccessFileOps {
  @patch
  factory _RandomAccessFileOps._(int pointer) => _SystemFile(pointer);
}

/// A file that the system knows as [fd].
class _SystemFile implements _RandomAccessFileOps {
  int fd;

  /// The file that is called [pointer], which is never 0.
  _SystemFile(int pointer) : fd = pointer - 1;

  int _getPointer() => fd + 1;

  int close() {
    if (fd == 1) {
      // What is printed later goes nowhere.
      final path = FileSystemEntity._toUtf8Array('/dev/null');
      final nothing = _openPath(dataAddress(path), _writeOnly, 0);
      _duplicateFile(nothing, fd);
      _closeFile(nothing);
      return 0;
    }
    final result = _closeFile(fd);
    if (result < 0) return -1;
    fd = -1;
    return 0;
  }

  /// The number of bytes read to [target] from [start], of [count] at most.
  int _readTo(Uint8List target, int start, int count) {
    while (true) {
      final result = _readFile(fd, dataAddress(target) + start, count);
      if (result >= 0 || _errno != _eInterrupted) return result;
    }
  }

  readByte() {
    final byte = Uint8List(1);
    final count = _readTo(byte, 0, 1);
    return count < 0
        ? _failure()
        : count == 0
        ? -1
        : byte[0];
  }

  read(int bytes) {
    if (bytes < 0) return const OSError('Invalid argument');
    final result = Uint8List(bytes);
    final count = _readTo(result, 0, bytes);
    if (count < 0) return _failure();
    return count == bytes ? result : result.sublist(0, count);
  }

  readInto(List<int> buffer, int start, int? end) {
    final count = end! - start;
    if (buffer is Uint8List) {
      final result = _readTo(buffer, start, count);
      return result < 0 ? _failure() : result;
    }
    final bytes = read(count);
    if (bytes is! Uint8List) return bytes;
    buffer.setRange(start, start + bytes.length, bytes);
    return bytes.length;
  }

  writeByte(int value) => switch (writeFrom(Uint8List(1)..[0] = value, 0, 1)) {
    final OSError error => error,
    _ => 1,
  };

  writeFrom(List<int> buffer, int start, int? end) {
    final bytes = buffer as Uint8List;
    for (var at = start; at < end!;) {
      final count = _writeSome(bytes, at, end - at);
      if (count < 0) return _failure();
      at += count;
    }
    return null;
  }

  /// The number of bytes written of [source] from [start].
  int _writeSome(Uint8List source, int start, int count) {
    while (true) {
      final result = _writeFile(fd, dataAddress(source) + start, count);
      if (result >= 0 || _errno != _eInterrupted) return result;
    }
  }

  position() {
    final result = _seekFile(fd, 0, _fromCurrent);
    return _valueIf(result, result);
  }

  setPosition(int position) => _succeeded(_seekFile(fd, position, _fromStart));

  truncate(int length) => _succeeded(_truncateFile(fd, length));

  length() => _statFile(fd, _buffer) < 0 ? _failure() : _statSize;

  flush() => _succeeded(_syncFile(fd));

  lock(int lock, int start, int end) {
    const set = 8, setWaiting = 9, shared = 1, none = 2, exclusive = 3;
    store64(_buffer, start);
    store64(_buffer + 8, end == -1 ? 0 : end - start);
    store32(_buffer + 16, 0);
    final type = switch (lock) {
      0 => none,
      1 || 3 => shared,
      _ => exclusive,
    };
    store16(_buffer + 20, type);
    store16(_buffer + 22, _fromStart);
    return _succeeded(_controlFile(fd, lock > 2 ? setWaiting : set, _buffer));
  }
}
