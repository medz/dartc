// Watching files with inotify, as the official runtime does.

@Native<Int32 Function(Int32)>(symbol: 'inotify_init1')
external int _initNotify(int flags);

@Native<Int32 Function(Int32, Int64, Uint32)>(symbol: 'inotify_add_watch')
external int _addNotifyWatch(int file, int path, int mask);

@Native<Int32 Function(Int32, Int32)>(symbol: 'inotify_rm_watch')
external int _removeNotifyWatch(int file, int watch);

// What inotify tells.
const _inModify = 0x2, _inAttributes = 0x4, _inCloseWrite = 0x8;
const _inMovedTo = 0x80, _inMove = 0xc0, _inCreate = 0x100, _inDelete = 0x200;
const _inDeleteSelf = 0x400, _inMoveSelf = 0x800, _inIgnored = 0x8000;
const _inIsDirectory = 0x40000000;

_FileSystemWatcher _systemWatcher() => _InotifyFileSystemWatcher();

int _startWatcher() {
  const noWait = 0x800, closeOnRun = 0x80000;
  final file = _initNotify(noWait | closeOnRun);
  if (file < 0) throw _failure();
  return file;
}

int _watchPathOf(int watcher, String path, int events, bool recursive) {
  var mask = _inDeleteSelf | _inMoveSelf;
  if (events & FileSystemEvent.create != 0) mask |= _inCreate;
  if (events & FileSystemEvent.modify != 0) {
    mask |= _inCloseWrite | _inAttributes | _inModify;
  }
  if (events & FileSystemEvent.delete != 0) mask |= _inDelete;
  if (events & FileSystemEvent.move != 0) mask |= _inMove;
  String canonical;
  try {
    canonical = File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    canonical = path;
  }
  final bytes = FileSystemEntity._toUtf8Array(canonical);
  final watch = _addNotifyWatch(watcher, dataAddress(bytes), mask);
  if (watch < 0) throw _failure();
  return watch;
}

void _unwatchPathOf(int watcher, int pathId) =>
    _removeNotifyWatch(watcher, pathId);

int _maskOf(int mask) =>
    (mask & (_inCloseWrite | _inModify) != 0 ? FileSystemEvent.modify : 0) |
    (mask & _inAttributes != 0 ? FileSystemEvent._modifyAttributes : 0) |
    (mask & _inCreate != 0 ? FileSystemEvent.create : 0) |
    (mask & _inMove != 0 ? FileSystemEvent.move : 0) |
    (mask & _inMovedTo != 0 ? FileSystemEvent._movedTo : 0) |
    (mask & _inDelete != 0 ? FileSystemEvent.delete : 0) |
    (mask & (_inDeleteSelf | _inMoveSelf) != 0
        ? FileSystemEvent._deleteSelf
        : 0) |
    (mask & _inIsDirectory != 0 ? FileSystemEvent._isDir : 0);

List _readEventsOf(int watcher) {
  const size = 16;
  final count = _readFile(watcher, _buffer, _bufferBytes);
  if (count <= 0) return const [];
  final events = [];
  for (var at = 0; at < count;) {
    final place = _buffer + at;
    final watch = load32(place), mask = load32(place + 4);
    final cookie = load32(place + 8), length = load32(place + 12);
    if (mask & _inIgnored == 0) {
      events.add([
        _maskOf(mask),
        cookie,
        length == 0 ? null : _textAt(place + size),
        watch,
      ]);
    }
    at += size + length;
  }
  return events;
}
