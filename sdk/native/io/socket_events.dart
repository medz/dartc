// What the event handler of the official runtime does for sockets, on the
// program's event loop: it tells a socket what happened, as events.

/// Waits for a socket to be ready to read or to write.
final class _SocketTask extends _Task {
  final _NativeSocket _owner;
  final bool isWriting;
  _SocketTask(this._owner, {required this.isWriting});

  int get file => _owner._socket;

  bool advance() => _owner._ready(isWriting: isWriting);
}

@patch
base class _NativeSocket {
  @patch
  Object? eventPort;

  /// What it waits for, if it waits.
  _SocketTask? _reading, _writing;

  /// The events that it is to be told of.
  int _wanted = 0;

  /// The error that was found while looking whether it can read, if any.
  int? _pendingError;

  @patch
  void _sendToEventHandler(int data) {
    connectToEventHandler();
    const events = 1 << readEvent | 1 << writeEvent;
    if (data & 1 << closeCommand != 0) {
      _stopWatching();
      if (_socket >= 0) _closeFile(_socket);
      _socket = -1;
      if (_place case final place?) _listening.remove(place);
      if (_unixPath case final path?) {
        final bytes = FileSystemEntity._toUtf8Array(path);
        _unlink(dataAddress(bytes));
      }
      scheduleMicrotask(() => multiplex(1 << destroyedEvent));
      return;
    }
    if (data & 1 << shutdownReadCommand != 0) _shutdown(_socket, 0);
    if (data & 1 << shutdownWriteCommand != 0) _shutdown(_socket, 1);
    if (data & 1 << setEventMaskCommand != 0) {
      _wanted = data & events;
      _watchAgain(isWriting: false);
      _watchAgain(isWriting: true);
    }
  }

  /// Whether it keeps the program going, as a socket that is not destroyed
  /// does officially.
  bool _keepsAlive = false;

  @patch
  void connectToEventHandler() {
    if (_keepsAlive) return;
    _keepsAlive = true;
    _Tasks._instance.keepers++;
  }

  @patch
  void disconnectFromEventHandler() {
    _stopWatching();
    if (!_keepsAlive) return;
    _keepsAlive = false;
    _Tasks._instance.keepers--;
  }

  /// Waits again to tell that it can read, or write, if that is wanted.
  void _watchAgain({required bool isWriting}) {
    if (_socket < 0) return;
    final event = isWriting ? writeEvent : readEvent;
    if (_wanted & 1 << event == 0) return;
    if (isWriting) {
      if (_writing != null) return;
      _Tasks._instance.add(_writing = _SocketTask(this, isWriting: true));
    } else {
      if (_reading != null) return;
      _Tasks._instance.add(_reading = _SocketTask(this, isWriting: false));
    }
  }

  void _stopWatching() {
    if (_reading case final task?) _Tasks._instance.remove(task);
    if (_writing case final task?) _Tasks._instance.remove(task);
    _reading = _writing = null;
  }

  /// Tells what happened now that it can read or write. Gives whether it is
  /// done waiting for that; it waits again once it is used.
  bool _ready({required bool isWriting}) {
    if (_socket < 0) return true;
    if (isWriting) {
      _writing = null;
      multiplex(1 << writeEvent);
      return true;
    }
    if (isListening || isUdp || _nativeAvailable() > 0) {
      _reading = null;
      multiplex(1 << readEvent);
      return true;
    }
    // Nothing to read is the end, or an error.
    final place = _allocateBytes(8);
    final result = _receive(_socket, place, 1, 2 | _noWaitMessage);
    _freeBytes(place);
    if (result < 0 && _errno == _eAgain) return false;
    // Looking took the error, which is kept to be asked for.
    if (result < 0) _pendingError = _errno;
    _reading = null;
    multiplex(1 << (result == 0 ? closedEvent : errorEvent));
    return true;
  }
}
