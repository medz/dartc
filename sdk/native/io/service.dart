import 'dart:_heap/objects.dart' show registerEvents;
import 'dart:_internal' show EventSource;

/// Work with files that is asked for and ends later.
abstract class _Task {
  /// The file that has to be ready, or -1.
  int get file => -1;

  /// Whether it has to be ready for writing.
  bool get isWriting => false;

  /// Whether the program waits for this task before exiting.
  bool get keepsAlive => true;

  /// Does some of it. Returns whether that was all.
  bool advance();
}

/// What has been done at once.
class _DoneTask extends _Task {
  final Completer<Object?> _completer;
  final Object? _result;

  _DoneTask(this._completer, this._result);

  bool advance() {
    _completer.complete(_result);
    return true;
  }
}

/// Reads what is there.
class _ReadTask extends _Task {
  final Completer<Object?> _completer;
  final int file;
  final Object? Function() _read;

  _ReadTask(this._completer, this.file, this._read);

  bool advance() {
    _completer.complete(_read());
    return true;
  }
}

/// Writes bytes to what may not take all of them now.
class _WriteTask extends _Task {
  /// How many bytes it takes if it is ready.
  static const _chunk = 512;

  final Completer<Object?> _completer;
  final _SystemFile _target;
  final Uint8List _source;
  final Object? _result;
  final int _end;
  int _at;

  _WriteTask(
    this._completer,
    this._target,
    this._source,
    this._at,
    this._end,
    this._result,
  );

  int get file => _target.fd;

  bool get isWriting => true;

  bool advance() {
    final count = _target._writeSome(_source, _at, min(_chunk, _end - _at));
    if (count < 0) {
      if (_errno == _eWouldBlock) return false;
      _completer.complete(_response(_failure()));
      return true;
    }
    _at += count;
    if (_at < _end) return false;
    _completer.complete(_result);
    return true;
  }
}

/// All such work.
class _Tasks implements EventSource {
  static final _Tasks _instance = _register();

  static _Tasks _register() {
    final tasks = _Tasks();
    registerEvents(tasks);
    return tasks;
  }

  final List<_Task> _waiting = [];

  void add(_Task task) => _waiting.add(task);

  void remove(_Task task) => _waiting.remove(task);

  bool get keepsAlive => _waiting.any((task) => task.keepsAlive);

  int get happened => _waiting.length;

  bool runOne() {
    if (_waiting.isEmpty) return false;
    final first = _waiting.first.file < 0 ? 0 : _lookAt(0);
    if (first < 0) return false;
    final task = _waiting.removeAt(first);
    if (task.advance()) return true;
    _waiting.add(task);
    return task.file >= 0;
  }

  void wait(int microseconds) {
    // A child without a waitable descriptor is checked with waitpid.
    const retry = 2000;
    final canWaitLong = microseconds < 0 || microseconds > retry;
    _lookAt(
      canWaitLong && _waiting.any((task) => task.file < 0)
          ? retry
          : microseconds,
    );
  }

  void end() {}

  /// The first task that can run, or -1 if no descriptor is ready.
  int _lookAt(int microseconds) {
    final size = _waiting.length * _pollEntryBytes;
    final files = size <= _bufferBytes ? _buffer : _allocateBytes(size);
    try {
      for (final (index, task) in _waiting.indexed) {
        _pollFile(
          files + index * _pollEntryBytes,
          task.file,
          isWriting: task.isWriting,
        );
      }
      final ready = _pollFiles(files, _waiting.length, microseconds);
      for (final (index, task) in _waiting.indexed) {
        if (task.file < 0 ||
            ready > 0 && _pollReady(files + index * _pollEntryBytes)) {
          return index;
        }
      }
      return -1;
    } finally {
      if (files != _buffer) _freeBytes(files);
    }
  }
}

/// [result] as [_checkForErrorResponse] takes it.
Object? _response(Object? result) => result is OSError
    ? [_osErrorResponse, result.errorCode, result.message]
    : result;

/// The listings of directories that have not ended, by their numbers.
final Map<int, _Listing> _listings = {};
int _listingCount = 0;

@patch
class _AsyncDirectoryListerOps {
  @patch
  factory _AsyncDirectoryListerOps._(int pointer) => _ListerOps(pointer);
}

class _ListerOps implements _AsyncDirectoryListerOps {
  final int _number;

  _ListerOps(this._number);

  int? _getPointer() => _number;
}

@patch
class _IOService {
  @patch
  static Future<Object?> _dispatch(int request, List data) {
    final completer = Completer<Object?>();
    _Tasks._instance.add(
      _withOpenFile(completer, request, data) ??
          _DoneTask(completer, _response(_answer(request, data))),
    );
    return completer.future;
  }

  /// What [request] is if it may have to wait until a file is ready.
  static _Task? _withOpenFile(
    Completer<Object?> completer,
    int request,
    List data,
  ) {
    if (request < fileReadByte || request > fileWriteFrom) return null;
    final open = _SystemFile(data[0]);
    switch (request) {
      case fileReadByte || fileRead || fileReadInto:
        return _ReadTask(completer, open.fd, () => _read(open, request, data));
    }
    final isByte = request == fileWriteByte;
    final bytes = isByte ? (Uint8List(1)..[0] = data[1]) : data[1];
    final int start = isByte ? 0 : data[2], end = isByte ? 1 : data[3];
    if (_statFile(open.fd) == 0 && _statMode & _modeType != _modeFile) {
      final copy = Uint8List.fromList(bytes);
      return _WriteTask(completer, open, copy, start, end, isByte ? 1 : null);
    }
    final result = open.writeFrom(bytes, start, end);
    return _DoneTask(
      completer,
      _response(result is OSError ? result : (isByte ? 1 : null)),
    );
  }

  static Object? _read(_SystemFile open, int request, List data) {
    if (request == fileReadByte) return _response(open.readByte());
    final result = open.read(data[1]);
    if (result is! Uint8List) return _response(result);
    return request == fileRead
        ? [_successResponse, result]
        : [_successResponse, result.length, result];
  }

  static Object? _answer(int request, List data) => switch (request) {
    <= fileStat =>
      request >= fileClose && request <= fileFlush && !_takesPath(request)
          ? _answerOpen(request, _SystemFile(data[0]), data)
          : _answerPath(request, data),
    fileLock => _SystemFile(data[0]).lock(data[1], data[2], data[3]),
    fileCreatePipe => _File._createPipe(_Namespace._namespace),
    _ => _answerDirectory(request, data),
  };

  static bool _takesPath(int request) =>
      request >= fileLengthFromPath && request <= fileSetLastModified;

  static Object? _answerOpen(int request, _SystemFile open, List data) =>
      switch (request) {
        fileClose => open.close(),
        filePosition => open.position(),
        fileSetPosition => open.setPosition(data[1]),
        fileTruncate => open.truncate(data[1]),
        fileLength => open.length(),
        _ => open.flush(),
      };

  static Object? _answerPath(int request, List data) {
    final space = _Namespace._namespace;
    switch (request) {
      case fileExists:
        return _File._exists(space, data[1]);
      case fileCreate:
        return _File._create(space, data[1], data[2]);
      case fileDelete:
        return _File._deleteNative(space, data[1]);
      case fileRename:
        return _File._rename(space, data[1], data[2]);
      case fileCopy:
        return _File._copy(space, data[1], data[2]);
      case fileOpen:
        return _File._open(space, data[1], data[2]);
      case fileResolveSymbolicLinks:
        return FileSystemEntity._resolveSymbolicLinks(space, data[1]);
      case fileLengthFromPath:
        return _File._lengthFromPath(space, data[1]);
      case fileLastAccessed:
        return _File._lastAccessed(space, data[1]);
      case fileSetLastAccessed:
        return _File._setLastAccessed(space, data[1], data[2]);
      case fileLastModified:
        return _File._lastModified(space, data[1]);
      case fileSetLastModified:
        return _File._setLastModified(space, data[1], data[2]);
      case fileCreateLink:
        return _File._createLink(space, data[1], data[2]);
      case fileDeleteLink:
        return _File._deleteLinkNative(space, data[1]);
      case fileRenameLink:
        return _File._renameLink(space, data[1], data[2]);
      case fileLinkTarget:
        return _File._linkTarget(space, data[1]);
      case fileType:
        return FileSystemEntity._getTypeNative(space, data[1], data[2]);
      case fileIdentical:
        return FileSystemEntity._identicalNative(space, data[1], data[2]);
      default:
        final stat = FileStat._statSync(space, data[1]);
        return stat is OSError ? stat : [_successResponse, stat];
    }
  }

  static Object? _answerDirectory(int request, List data) {
    final space = _Namespace._namespace;
    switch (request) {
      case directoryCreate:
        return _Directory._create(space, data[1]);
      case directoryDelete:
        return _Directory._deleteNative(space, data[1], data[2]);
      case directoryExists:
        return _Directory._exists(space, data[1]);
      case directoryCreateTemp:
        return _Directory._createTemp(space, data[1]);
      case directoryRename:
        return _Directory._rename(space, data[1], data[2]);
      case directoryListStart:
        final number = ++_listingCount;
        _listings[number] = _Listing(data[1], data[2], data[3]);
        return number;
      case directoryListNext:
        return _more(_listings[data[0]]!);
      case directoryListStop:
        _listings.remove(data[0])?.end();
        return true;
      default:
        throw UnsupportedError('This operation is not supported yet.');
    }
  }

  /// Some of the next entries of [listing], after the kind of each one.
  static List<Object?> _more(_Listing listing) {
    const most = 64;
    final result = <Object?>[];
    for (var i = 0; i < most; i++) {
      final kind = listing.next();
      result.add(kind);
      if (kind == _AsyncDirectoryLister.listDone) {
        result.add(null);
        break;
      }
      final path = listing.path;
      result.add(
        kind == _AsyncDirectoryLister.listError
            ? [_AsyncDirectoryLister.listError, path, _response(_failure())]
            : path,
      );
    }
    return result;
  }
}
