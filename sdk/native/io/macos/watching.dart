// Watching files with FSEvents, as the official runtime does. Streams are on
// the run loop of the program's thread, which a timer runs while any is there.
import 'dart:ffi'
    show
        Double,
        Int32,
        Int64,
        NativeFunction,
        Pointer,
        Uint8,
        Uint32,
        Uint64,
        Void,
        DynamicLibrary,
        DynamicLibraryExtension,
        NativeFunctionPointer;

final _services = DynamicLibrary.open(
  '/System/Library/Frameworks/CoreServices.framework/CoreServices',
);

final _createText = _services
    .lookupFunction<
      Int64 Function(Int64, Int64, Uint32),
      int Function(int, int, int)
    >('CFStringCreateWithCString');
final _createArray = _services
    .lookupFunction<
      Int64 Function(Int64, Int64, Int64, Int64),
      int Function(int, int, int, int)
    >('CFArrayCreate');
final _release = _services
    .lookupFunction<Void Function(Int64), void Function(int)>('CFRelease');
final _createStream = _services
    .lookupFunction<
      Int64 Function(Int64, Int64, Int64, Int64, Uint64, Double, Uint32),
      int Function(int, int, int, int, int, double, int)
    >('FSEventStreamCreate');
final _schedule = _services
    .lookupFunction<
      Void Function(Int64, Int64, Int64),
      void Function(int, int, int)
    >('FSEventStreamScheduleWithRunLoop');
final _startStream = _services
    .lookupFunction<Uint8 Function(Int64), int Function(int)>(
      'FSEventStreamStart',
    );
final _flushStream = _services
    .lookupFunction<Void Function(Int64), void Function(int)>(
      'FSEventStreamFlushSync',
    );
final _stopStream = _services
    .lookupFunction<Void Function(Int64), void Function(int)>(
      'FSEventStreamStop',
    );
final _invalidateStream = _services
    .lookupFunction<Void Function(Int64), void Function(int)>(
      'FSEventStreamInvalidate',
    );
final _releaseStream = _services
    .lookupFunction<Void Function(Int64), void Function(int)>(
      'FSEventStreamRelease',
    );
final _mainLoop = _services.lookupFunction<Int64 Function(), int Function()>(
  'CFRunLoopGetMain',
);
final _runLoop = _services
    .lookupFunction<
      Int32 Function(Int64, Double, Int32),
      int Function(int, double, int)
    >('CFRunLoopRunInMode');
final int _defaultMode = load64(
  _services.lookup<Void>('kCFRunLoopDefaultMode').address,
);

// What FSEvents tells.
const _itemCreated = 0x100, _itemRemoved = 0x200, _itemRenamed = 0x800;
const _itemModified = 0x1000, _itemXattrMod = 0x8000, _itemIsDir = 0x20000;

/// A path that a stream watches.
final class _Node {
  final int stream, baseLength;
  final bool recursive;
  _Node(this.stream, this.baseLength, this.recursive);
}

final Map<int, _Node> _nodes = {};
int _lastNode = 0;

/// What the streams told, by bundle, until it is handed on.
final List<List> _bundles = [];

_FileSystemWatcher _systemWatcher() => _RunLoopFileSystemWatcher();

int _startWatcher() => 0;

int _watchPathOf(int watcher, String path, int events, bool recursive) {
  final base = File(path).resolveSymbolicLinksSync();
  final id = ++_lastNode;
  final text = _cString(base);
  final name = _createText(0, text, 0x08000100);
  _freeBytes(text);
  final names = _allocateBytes(8);
  store64(names, name);
  final array = _createArray(0, names, 1, 0);
  _freeBytes(names);
  // The version, what callbacks get, and functions that are not there.
  final context = _allocateBytes(40);
  store64(context, 0);
  store64(context + 8, id);
  for (var i = 16; i < 40; i += 8) {
    store64(context + i, 0);
  }
  const sinceNow = -1, latency = 0.10, fileEvents = 0x10;
  final stream = _createStream(
    0,
    _eventsCallback.address,
    context,
    array,
    sinceNow,
    latency,
    fileEvents,
  );
  _freeBytes(context);
  _release(array);
  _release(name);
  if (stream == 0) {
    throw FileSystemException('Failed to create FSEvents stream', path);
  }
  _schedule(stream, _mainLoop(), _defaultMode);
  // Flushing calls back at once, so the node is there before it.
  _nodes[id] = _Node(stream, utf8.encode(base).length, recursive);
  if (_startStream(stream) == 0) {
    _nodes.remove(id);
    _invalidateStream(stream);
    _releaseStream(stream);
    throw FileSystemException('Failed to start FSEvents stream', path);
  }
  _flushStream(stream);
  return id;
}

void _unwatchPathOf(int watcher, int pathId) {
  final node = _nodes.remove(pathId);
  if (node == null) return;
  _stopStream(node.stream);
  _invalidateStream(node.stream);
  _releaseStream(node.stream);
}

List _readEventsOf(int watcher) => const [];

final _eventsCallback =
    Pointer.fromFunction<
      Void Function(Int64, Int64, Int64, Int64, Int64, Int64)
    >(_takeEvents);

/// Notes what a stream tells, as the official runtime converts it.
void _takeEvents(
  int stream,
  int info,
  int count,
  int paths,
  int flags,
  int ids,
) {
  final node = _nodes[info];
  if (node == null) return;
  final bundle = [];
  for (var i = 0; i < count; i++) {
    final path = load64(paths + i * 8);
    final full = _bytesAt(path, _lengthAt(path));
    // When events were dropped, the path may be `/`, above the watched one.
    if (full.length < node.baseLength) continue;
    var start = node.baseLength;
    if (start < full.length && full[start] == 0x2f) start++;
    final relative = utf8.decode(full.sublist(start), allowMalformed: true);
    if (!node.recursive && relative.contains('/')) continue;
    final isSelf = relative.isEmpty;
    final exists =
        _anyTypeAt(Uint8List.fromList([...full, 0]), false) != _typeNone;
    final mask = _maskOf(load32(flags + i * 4), isSelf, exists);
    bundle.add([mask, 0, relative, info]);
  }
  if (bundle.isNotEmpty) _bundles.add(bundle);
}

int _maskOf(int flags, bool isSelf, bool exists) {
  var mask = 0;
  if (flags & _itemRenamed != 0) {
    mask |= isSelf
        ? FileSystemEvent._deleteSelf
        : exists
        ? FileSystemEvent.create
        : FileSystemEvent.delete;
  }
  if (flags & _itemModified != 0) mask |= FileSystemEvent.modify;
  if (flags & _itemXattrMod != 0) mask |= FileSystemEvent._modifyAttributes;
  if (flags & _itemCreated != 0) mask |= FileSystemEvent.create;
  if (flags & _itemIsDir != 0) mask |= FileSystemEvent._isDir;
  if (flags & _itemRemoved != 0) {
    mask |= isSelf ? FileSystemEvent._deleteSelf : FileSystemEvent.delete;
  }
  return mask;
}

class _RunLoopFileSystemWatcher extends _MultiplexingFileSystemWatcher {
  Timer? _timer;

  @override
  void _ensureWatcherIsRunning() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 20), (_) => _run());
  }

  @override
  FutureOr<void> _stopWatcher() {
    _timer?.cancel();
    _timer = null;
  }

  /// Lets the streams tell what happened, then hands that on.
  void _run() {
    _runLoop(_defaultMode, 0, 0);
    while (_bundles.isNotEmpty) {
      final events = _bundles.removeAt(0);
      // All events in a bundle have the same pathId.
      final pathId = _NativeFSEvent(events[0] as List).pathId;
      if (_watchedPaths[pathId] case final watchedPath?) {
        for (final event in events) {
          watchedPath.addEvent(_NativeFSEvent(event as List));
        }
        watchedPath.flushUnmatchedMoves();
      }
    }
  }
}
