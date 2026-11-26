// Sockets: what the official `_NativeSocket` asks of the system, and the event
// handler that tells it what happens, on the program's event loop.
import 'dart:_heap/machine.dart' show load16, load32, store16, store32, store8;
import 'dart:ffi' show Int32, Int64, Native;

@Native<Int32 Function(Int32, Int32, Int32)>(symbol: 'socket')
external int _openSocket(int family, int type, int protocol);

@Native<Int32 Function(Int32, Int64, Int32)>(symbol: 'connect')
external int _connect(int socket, int address, int length);

@Native<Int32 Function(Int32, Int64, Int32)>(symbol: 'bind')
external int _bind(int socket, int address, int length);

@Native<Int32 Function(Int32, Int32)>(symbol: 'listen')
external int _listen(int socket, int backlog);

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'accept')
external int _accept(int socket, int address, int length);

@Native<Int64 Function(Int32, Int64, Int64, Int32)>(symbol: 'recv')
external int _receive(int socket, int buffer, int count, int flags);

@Native<Int64 Function(Int32, Int64, Int64, Int32)>(symbol: 'send')
external int _send(int socket, int buffer, int count, int flags);

@Native<Int64 Function(Int32, Int64, Int64, Int32, Int64, Int64)>(
  symbol: 'recvfrom',
)
external int _receiveFrom(
  int socket,
  int buffer,
  int count,
  int flags,
  int address,
  int length,
);

@Native<Int64 Function(Int32, Int64, Int64, Int32, Int64, Int32)>(
  symbol: 'sendto',
)
external int _sendTo(
  int socket,
  int buffer,
  int count,
  int flags,
  int address,
  int length,
);

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'getsockname')
external int _localName(int socket, int address, int length);

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'getpeername')
external int _peerName(int socket, int address, int length);

@Native<Int32 Function(Int32, Int32, Int32, Int64, Int64)>(symbol: 'getsockopt')
external int _getOption(int socket, int level, int name, int value, int size);

@Native<Int32 Function(Int32, Int32, Int32, Int64, Int32)>(symbol: 'setsockopt')
external int _setOption(int socket, int level, int name, int value, int size);

@Native<Int32 Function(Int32, Int32)>(symbol: 'shutdown')
external int _shutdown(int socket, int how);

@patch
int get _inProgressErrorCode => _eInProgress;

/// A socket of [family] and [type] that does not wait, or -1.
int _newSocket(int family, int type) {
  final socket = _openSocket(family, _socketType(type), 0);
  if (socket < 0) return socket;
  _keepFile(socket);
  _setNoSignal(socket);
  const getFlags = 3, setFlags = 4;
  _controlFile(
    socket,
    setFlags,
    _controlFile(socket, getFlags, 0) | _nonBlocking,
  );
  return socket;
}

/// Sets option [name] of [level] of [socket] to the integer [value].
int _setInteger(int socket, int level, int name, int value) {
  final place = _allocateBytes(4);
  store32(place, value);
  final result = _setOption(socket, level, name, place, 4);
  _freeBytes(place);
  return result;
}

/// The integer of option [name] of [level] of [socket], or the error.
Object _integerOption(int socket, int level, int name) {
  final place = _allocateBytes(8);
  store32(place, 0);
  store32(place + 4, 4);
  final result = _getOption(socket, level, name, place, place + 4);
  final value = load32(place);
  _freeBytes(place);
  return result < 0 ? _failure() : value;
}

/// [data] from [offset] as bytes whose address can be given to the system.
Uint8List _bytesOf(List<int> data, int offset, int count) =>
    data is Uint8List && data.offsetInBytes == 0 && offset == 0
    ? data
    : Uint8List.fromList(data.sublist(offset, offset + count));

/// A path of a Unix domain socket as the system has it.
(int, int) _unixAddress(String path) {
  final bytes = utf8.encode(path);
  final address = _allocateBytes(112);
  for (var i = 0; i < 112; i += 4) {
    store32(address + i, 0);
  }
  _setFamily(address, _afUnix, 106);
  for (var i = 0; i < bytes.length && i < 103; i++) {
    store8(address + 2 + i, bytes[i]);
  }
  return (address, _unixLength);
}

/// The places where sockets of the program listen, and whether they share.
final Map<String, bool> _listening = {};

@patch
base class _NativeSocket {
  int _socket = -1;

  @patch
  void _nativeSetSocketId(int id, int typeFlags) {
    _socket = id;
  }

  @patch
  int _nativeAvailable() {
    final place = _allocateBytes(8);
    store32(place, 0);
    _controlDevice(_socket, _bytesToRead, place);
    final count = load32(place);
    _freeBytes(place);
    return count;
  }

  @patch
  bool _nativeAvailableDatagram() {
    final place = _allocateBytes(8);
    final result = _receive(_socket, place, 1, 2 | _noWaitMessage);
    _freeBytes(place);
    return result >= 0;
  }

  @patch
  Uint8List? _nativeRead(int len) {
    _watchAgain(isWriting: false);
    final buffer = Uint8List(len);
    final count = _receive(_socket, dataAddress(buffer), len, 0);
    if (count < 0) {
      if (_errno == _eAgain) return null;
      throw _failure();
    }
    return count == 0 ? null : buffer.sublist(0, count);
  }

  @patch
  Datagram? _nativeRecvFrom() {
    _watchAgain(isWriting: false);
    final buffer = Uint8List(65536), address = _allocateBytes(128);
    store32(address + 120, 112);
    final count = _receiveFrom(
      _socket,
      dataAddress(buffer),
      buffer.length,
      0,
      address,
      address + 120,
    );
    final from = count < 0 ? null : _addressAt(address);
    _freeBytes(address);
    if (count < 0) {
      if (_errno == _eAgain) return null;
      throw _failure();
    }
    final (type, text, raw, port) = from!;
    return Datagram(
      buffer.sublist(0, count),
      _InternetAddress(InternetAddressType._from(type), text, null, raw),
      port,
    );
  }

  @patch
  int _nativeWrite(List<int> buffer, int offset, int bytes) {
    final data = _bytesOf(buffer, offset, bytes);
    final count = _send(_socket, dataAddress(data), bytes, _sendFlags);
    if (count < 0) {
      if (_errno != _eAgain) throw _failure();
      _watchAgain(isWriting: true);
      return 0;
    }
    if (count < bytes) _watchAgain(isWriting: true);
    return count;
  }

  @patch
  bool _nativeHasPendingWrite() => false;

  @patch
  int _nativeSendTo(
    List<int> buffer,
    int offset,
    int bytes,
    Uint8List address,
    int port,
  ) {
    final data = _bytesOf(buffer, offset, bytes);
    final (to, length) = _socketAddress(address, port);
    final count = _sendTo(_socket, dataAddress(data), bytes, 0, to, length);
    _freeBytes(to);
    if (count < 0) {
      if (_errno == _eAgain) return 0;
      throw _failure();
    }
    return count;
  }

  /// Makes a socket for [address], and connects it to that unless [connects]
  /// is false, after binding it to [source] if there is one.
  Object _make(
    (int, int) address,
    int family,
    int type, {
    (int, int)? source,
    bool connects = true,
  }) {
    final socket = _newSocket(family, type);
    if (socket < 0) return _failure();
    var result = 0;
    if (source != null) {
      _setInteger(socket, _solSocket, _soReuseAddress, 1);
      result = _bind(socket, source.$1, source.$2);
      _freeBytes(source.$1);
    }
    if (result == 0 && connects) {
      result = _connect(socket, address.$1, address.$2);
      if (result < 0 && _errno == _eInProgress) result = 0;
    }
    _freeBytes(address.$1);
    if (result < 0) {
      final error = _failure();
      _closeFile(socket);
      return error;
    }
    _socket = socket;
    return true;
  }

  @patch
  _nativeCreateConnect(Uint8List addr, int port, int scope_id) => _make(
    _socketAddress(addr, port, scope_id),
    _familyOf(addr),
    _streamSocket,
  );

  @patch
  _nativeCreateBindConnect(
    Uint8List addr,
    int port,
    Uint8List sourceAddr,
    int sourcePort,
    int scope_id,
  ) => _make(
    _socketAddress(addr, port, scope_id),
    _familyOf(addr),
    _streamSocket,
    source: _socketAddress(sourceAddr, sourcePort),
  );

  @patch
  _nativeCreateUnixDomainConnect(String addr, _Namespace namespace) =>
      _make(_unixAddress(addr), _afUnix, _streamSocket);

  @patch
  _nativeCreateUnixDomainBindConnect(
    String addr,
    String local,
    _Namespace namespace,
  ) => _make(
    _unixAddress(addr),
    _afUnix,
    _streamSocket,
    source: _unixAddress(local),
  );

  @patch
  bool isBindError(int errorNumber) =>
      errorNumber == _eAddressInUse ||
      errorNumber == _eAddressNotAvailable ||
      errorNumber == 22;

  /// Binds a new socket of [family] and [type] to [address], and lets it
  /// listen if it is a stream.
  Object _bound(
    (int, int) address,
    int family,
    int type, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
    bool reuseAddress = true,
  }) {
    final socket = _newSocket(family, type);
    if (socket < 0) {
      _freeBytes(address.$1);
      return _failure();
    }
    if (reuseAddress && family != _afUnix) {
      _setInteger(socket, _solSocket, _soReuseAddress, 1);
    }
    if (shared) _setInteger(socket, _solSocket, _soReusePort, 1);
    if (family == _afInet6) _setInteger(socket, 41, _ipv6Only, v6Only ? 1 : 0);
    var result = _bind(socket, address.$1, address.$2);
    _freeBytes(address.$1);
    if (result == 0 && type == _streamSocket) {
      result = _listen(socket, backlog == 0 ? 128 : backlog);
    }
    if (result < 0) {
      final error = _failure();
      _closeFile(socket);
      return error;
    }
    _socket = socket;
    return true;
  }

  @patch
  _nativeCreateBindListen(
    Uint8List addr,
    int port,
    int backlog,
    bool v6Only,
    bool shared,
    int scope_id,
  ) {
    // As officially, sockets of the program that listen at one place have to
    // be shared.
    if (_listening['$addr:$port'] case final other? when port != 0) {
      if (!shared || !other) {
        return const OSError(
          'The shared flag to bind() needs to be `true` if binding multiple '
          'times on the same (address, port) combination.',
        );
      }
    }
    final result = _bound(
      _socketAddress(addr, port, scope_id),
      _familyOf(addr),
      _streamSocket,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    );
    if (result == true) {
      _place = '$addr:${_nativeGetPort()}';
      _listening[_place!] = shared;
    }
    return result;
  }

  /// Where it listens, if it is noted in [_listening].
  String? _place;

  /// The path of the Unix domain socket that it listens at, which goes when
  /// it is closed.
  String? _unixPath;

  @patch
  _nativeCreateUnixDomainBindListen(
    String addr,
    int backlog,
    bool shared,
    _Namespace namespace,
  ) {
    final result = _bound(
      _unixAddress(addr),
      _afUnix,
      _streamSocket,
      backlog: backlog,
    );
    if (result == true) _unixPath = addr;
    return result;
  }

  @patch
  _nativeCreateBindDatagram(
    Uint8List addr,
    int port,
    bool reuseAddress,
    bool reusePort,
    int ttl,
  ) {
    final result = _bound(
      _socketAddress(addr, port),
      _familyOf(addr),
      _datagramSocket,
      reuseAddress: reuseAddress,
      shared: reusePort,
    );
    if (result == true) {
      final isIPv4 = addr.length == 4;
      _setInteger(
        _socket,
        isIPv4 ? 0 : 41,
        isIPv4 ? _ipMulticastTtl : _ipv6MulticastHops,
        ttl,
      );
    }
    return result;
  }

  @patch
  bool _nativeAccept(_NativeSocket socket) {
    _watchAgain(isWriting: false);
    final accepted = _accept(_socket, 0, 0);
    if (accepted < 0) return false;
    _keepFile(accepted);
    _setNoSignal(accepted);
    const getFlags = 3, setFlags = 4;
    _controlFile(
      accepted,
      setFlags,
      _controlFile(accepted, getFlags, 0) | _nonBlocking,
    );
    socket._socket = accepted;
    return true;
  }

  @patch
  dynamic _nativeGetPort() {
    final address = _allocateBytes(128);
    store32(address + 120, 112);
    final result = _localName(_socket, address, address + 120);
    final port = load8(address + 2) << 8 | load8(address + 3);
    _freeBytes(address);
    return result < 0 ? _failure() : port;
  }

  @patch
  List _nativeGetRemotePeer() {
    final address = _allocateBytes(128);
    store32(address + 120, 112);
    final result = _peerName(_socket, address, address + 120);
    if (result < 0) {
      _freeBytes(address);
      throw _failure();
    }
    final told = _addressAt(address);
    final peer = told == null
        ? [
            [2, _textAt(address + 2)],
            0,
          ]
        : [
            [told.$1, told.$2, told.$3],
            told.$4,
          ];
    _freeBytes(address);
    return peer;
  }

  @patch
  int _nativeGetSocketId() => _socket;

  @patch
  int get fd => _socket;

  @patch
  OSError? _nativeGetError() {
    if (_pendingError case final pending?) {
      _pendingError = null;
      return _failure(pending);
    }
    final code = _integerOption(_socket, _solSocket, _soError);
    return code is int && code != 0 ? _failure(code) : null;
  }

  @patch
  _nativeGetOption(int option, int protocol) {
    final (level, name) = _optionOf(option, protocol);
    final value = _integerOption(_socket, level, name);
    if (value is! int) return value;
    return option == 2 ? value : value != 0;
  }

  @patch
  void _nativeSetOption(int option, int protocol, value) {
    final (level, name) = _optionOf(option, protocol);
    final number = value is bool ? (value ? 1 : 0) : value as int;
    if (_setInteger(_socket, level, name, number) < 0) throw _failure();
  }

  /// The level and name of [option] for sockets of [protocol].
  static (int, int) _optionOf(int option, int protocol) {
    final isIPv4 = protocol != 1;
    return switch (option) {
      0 => (6, 1),
      1 => isIPv4 ? (0, _ipMulticastLoop) : (41, _ipv6MulticastLoop),
      2 => isIPv4 ? (0, _ipMulticastTtl) : (41, _ipv6MulticastHops),
      4 => (_solSocket, _soBroadcast),
      _ => throw UnsupportedError('This socket option'),
    };
  }

  @patch
  void _nativeGetRawOption(int level, int option, Uint8List data) {
    final place = _allocateBytes(8);
    store32(place, data.length);
    final result = _getOption(_socket, level, option, dataAddress(data), place);
    _freeBytes(place);
    if (result < 0) throw _failure();
  }

  @patch
  void _nativeSetRawOption(int level, int option, Uint8List data) {
    final result = _setOption(
      _socket,
      level,
      option,
      dataAddress(data),
      data.length,
    );
    if (result < 0) throw _failure();
  }

  @patch
  void _nativeJoinMulticast(
    Uint8List addr,
    Uint8List? interfaceAddr,
    int interfaceIndex,
  ) => _membership(addr, interfaceAddr, interfaceIndex, joins: true);

  @patch
  void _nativeLeaveMulticast(
    Uint8List addr,
    Uint8List? interfaceAddr,
    int interfaceIndex,
  ) => _membership(addr, interfaceAddr, interfaceIndex, joins: false);

  void _membership(
    Uint8List address,
    Uint8List? interface,
    int index, {
    required bool joins,
  }) {
    final request = _allocateBytes(20), isIPv4 = address.length == 4;
    for (var i = 0; i < address.length; i++) {
      store8(request + i, address[i]);
    }
    for (var i = 0; i < 4; i++) {
      final byte = isIPv4 && interface != null ? interface[i] : 0;
      store8(request + address.length + i, byte);
    }
    if (!isIPv4) store32(request + 16, index);
    final name = isIPv4
        ? joins
              ? _ipAddMembership
              : _ipDropMembership
        : joins
        ? _ipv6JoinGroup
        : _ipv6LeaveGroup;
    final result = _setOption(
      _socket,
      isIPv4 ? 0 : 41,
      name,
      request,
      isIPv4 ? 8 : 20,
    );
    _freeBytes(request);
    if (result < 0) throw _failure();
  }

  @patch
  static void _nativeFatal(msg) => throw StateError('$msg');
}
