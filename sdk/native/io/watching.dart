// Watching files: what the official watchers use, without sockets or ports.

@patch
class _WatchedPath {
  // Paths are let go of when they are no longer listened to.
  @patch
  static final ffi.NativeFinalizer? finalizer = null;

  @patch
  _WatchedPath(this.pathId, this.path, this.events);

  @patch
  FutureOr<void> dispose() {
    isClosed = true;
    return source?.cancel();
  }

  @patch
  String fullPathOf(_NativeFSEvent event) {
    assert(event.pathId == pathId);
    if (event.relativePath case final relative? when relative.isNotEmpty) {
      final separator = path.endsWith('/') ? '' : '/';
      return '$path$separator$relative';
    }
    return path;
  }
}

@patch
abstract class _FileSystemWatcher {
  @patch
  static bool get isSupported => true;

  @patch
  static Stream<FileSystemEvent> _watch(
    String path,
    int events,
    bool recursive,
  ) {
    final stream = _watcher._watchImpl(path, events, recursive);
    if (events == FileSystemEvent.all) return stream;
    return stream.where((event) => event.type & events != 0);
  }

  @patch
  Stream<List<_NativeFSEvent>> _eventsStreamFromSocket(
    int socketId,
    int pathId,
  ) {
    late final _WatchTask task;
    final controller = StreamController<List<_NativeFSEvent>>(
      sync: true,
      onListen: () => _Tasks._instance.add(task),
      onCancel: () {
        _Tasks._instance.remove(task);
        _closeFile(socketId);
      },
    );
    task = _WatchTask(socketId, () {
      final result = <_NativeFSEvent>[];
      while (true) {
        final events = _readEvents(_watcherId, pathId);
        if (events.isEmpty) break;
        for (final event in events) {
          result.add(_NativeFSEvent(event as List));
        }
      }
      if (result.isNotEmpty) controller.add(result);
    });
    return controller.stream;
  }

  @patch
  static _FileSystemWatcher _watcher = _systemWatcher();

  @patch
  static int _initWatcher() => _startWatcher();

  @patch
  static int _watchPathImpl(
    int watcherId,
    _Namespace namespace,
    String path,
    int events,
    bool recursive,
  ) => _watchPathOf(watcherId, path, events, recursive);

  @patch
  static void _unwatchPath(int watcherId, int pathId) =>
      _unwatchPathOf(watcherId, pathId);

  @patch
  static List _readEvents(int watcherId, int pathId) =>
      _readEventsOf(watcherId);

  @patch
  static int _getSocketId(int watcherId, int pathId) => watcherId;
}

@patch
abstract class _MultiplexingFileSystemWatcher extends _FileSystemWatcher {
  @patch
  _WatchedPath _startWatching(String path, int events, bool recursive) {
    _ensureWatcherIsRunning();
    try {
      final pathId = super._watchPath(path, events, recursive);
      assert(Platform.isLinux || !_watchedPaths.containsKey(pathId));
      // Inotify can reuse a path. Each returned stream applies its own mask.
      return _watchedPaths[pathId] ??= _WatchedPath(
        pathId,
        path,
        FileSystemEvent.all,
      );
    } on FileSystemException {
      if (_watchedPaths.isEmpty) _stopWatcher();
      rethrow;
    }
  }
}

/// Reads what a watcher has whenever its file is ready.
final class _WatchTask extends _Task {
  final int _file;
  final void Function() _read;
  _WatchTask(this._file, this._read);

  int get file => _file;

  bool advance() {
    _read();
    return false;
  }
}
