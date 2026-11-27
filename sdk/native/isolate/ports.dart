// Ports, which take messages for the isolate that has them.

@patch
class ReceivePort {
  @patch
  factory ReceivePort([String debugName = '']) => _ReceivePortImpl(debugName);

  @patch
  factory ReceivePort.fromRawReceivePort(RawReceivePort rawPort) =>
      _ReceivePortImpl.fromRawReceivePort(rawPort);
}

@patch
class Capability {
  @patch
  factory Capability() => _CapabilityImpl(_newCapability());
}

final class _CapabilityImpl implements Capability {
  final int _number;

  _CapabilityImpl(this._number);

  bool operator ==(Object other) =>
      other is _CapabilityImpl && other._number == _number;

  int get hashCode => _number.hashCode;
}

@patch
class RawReceivePort {
  @patch
  factory RawReceivePort([Function? handler, String debugName = '']) =>
      _RawReceivePortImpl()..handler = handler;
}

/// Like the official one, a stream of what a raw port takes.
final class _ReceivePortImpl extends Stream implements ReceivePort {
  _ReceivePortImpl([String debugName = ''])
    : this.fromRawReceivePort(RawReceivePort(null, debugName));

  _ReceivePortImpl.fromRawReceivePort(this._rawPort)
    : _controller = StreamController(sync: true) {
    _controller.onCancel = close;
    _rawPort.handler = _controller.add;
  }

  final RawReceivePort _rawPort;
  final StreamController _controller;

  SendPort get sendPort => _rawPort.sendPort;

  StreamSubscription listen(
    void onData(message)?, {
    Function? onError,
    void onDone()?,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void close() {
    _rawPort.close();
    _controller.close();
  }
}

final class _RawReceivePortImpl implements RawReceivePort {
  final int _number;
  Function? _handler;
  bool _isOpen = true, _keepsAlive = true;

  _RawReceivePortImpl() : _number = _Inbox.current.newPort() {
    final inbox = _Inbox.current;
    inbox.ports[_number] = this;
    inbox.keepers++;
  }

  void set handler(Function? value) {
    _handler = value;
  }

  SendPort get sendPort => _SendPortImpl(_number, _Inbox.current.address);

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    final inbox = _Inbox.current;
    inbox.ports.remove(_number);
    if (_keepsAlive) inbox.keepers--;
  }

  bool get keepIsolateAlive => _keepsAlive;

  void set keepIsolateAlive(bool value) {
    if (_isOpen && value != _keepsAlive) {
      _Inbox.current.keepers += value ? 1 : -1;
    }
    _keepsAlive = value;
  }

  bool operator ==(Object other) =>
      other is _RawReceivePortImpl && other._number == _number;

  int get hashCode => sendPort.hashCode;
}

final class _SendPortImpl implements SendPort {
  final int _number;

  /// The inbox of the isolate that has the port.
  final int _inbox;

  _SendPortImpl(this._number, this._inbox);

  void send(Object? message) => _send(_inbox, _number, message);

  bool operator ==(Object other) =>
      other is _SendPortImpl &&
      other._number == _number &&
      other._inbox == _inbox;

  int get hashCode => _number.hashCode;
}
