// Secure sockets: a filter that moves bytes between the buffers of the
// official `_RawSecureSocket` through the TLS of the system (`_Engine`).

@patch
class _RawSecureSocket {
  @patch
  _NoPort? keyLogPort;

  @patch
  _RawSecureSocket(
    this.address,
    int requestedPort,
    this.isServer,
    this.context,
    this._socket,
    StreamSubscription<RawSocketEvent>? subscription,
    this._bufferedData,
    this.requestClientCertificate,
    this.requireClientCertificate,
    this.onBadCertificate,
    this.keyLog,
    List<String>? supportedProtocols,
  ) {
    _controller
      ..onListen = _onSubscriptionStateChange
      ..onPause = _onPauseStateChange
      ..onResume = _onPauseStateChange
      ..onCancel = _onSubscriptionStateChange;
    // Throw an ArgumentError if any field is invalid.  After this, all
    // errors will be reported through the future or the stream.
    final secureFilter = _secureFilter!;
    secureFilter.init();
    secureFilter.registerHandshakeCompleteCallback(
      _secureHandshakeCompleteHandler,
    );

    // The filter tells the key log itself.
    if (keyLog case final log?) secureFilter.registerKeyLog(log);

    if (onBadCertificate != null) {
      secureFilter.registerBadCertificateCallback(_onBadCertificateWrapper);
    }
    _socket.readEventsEnabled = true;
    _socket.writeEventsEnabled = false;
    if (subscription == null) {
      // If a current subscription is provided use this otherwise
      // create a new one.
      _socketSubscription = _socket.listen(
        _eventDispatcher,
        onError: _reportError,
        onDone: _doneHandler,
      );
    } else {
      _socketSubscription = subscription;
      if (_socketSubscription.isPaused) {
        _socket.close();
        throw ArgumentError("Subscription passed to TLS upgrade is paused");
      }
      // If we are upgrading a socket that is already closed for read,
      // report an error as if we received readClosed during the handshake.
      if (_closedReadEventSent) {
        _eventDispatcher(RawSocketEvent.readClosed);
      }
      _socketSubscription
        ..onData(_eventDispatcher)
        ..onError(_reportError)
        ..onDone(_doneHandler);
    }
    try {
      var encodedProtocols = SecurityContext._protocolsToLengthEncoding(
        supportedProtocols,
      );
      secureFilter.connect(
        address.host,
        context,
        isServer,
        requestClientCertificate || requireClientCertificate,
        requireClientCertificate,
        encodedProtocols,
      );
      _secureHandshake();
    } catch (e, s) {
      _reportError(e, s);
    }
  }
}

@patch
class _SecureFilter {
  @patch
  factory _SecureFilter._() => _SystemFilter();

  /// Tells [log] the lines of the key log.
  void registerKeyLog(void Function(String line) log);
}

@patch
base class _SecureFilterImpl {
  void registerKeyLog(void Function(String line) log) {}
}

/// What would be the port of the key log, which there never is.
final class _NoPort {
  void close() {}
}

@patch
class SecurityContext {
  @patch
  factory SecurityContext({bool withTrustedRoots = false}) =>
      _Context(withTrustedRoots);

  @patch
  static SecurityContext get defaultContext => _Context.defaultContext;
}

@patch
class X509Certificate {
  @patch
  factory X509Certificate._() => throw UnsupportedError('X509Certificate');
}

/// The filters by the numbers that the IO service is given.
final Map<int, _SystemFilter> _filters = {};
int _lastFilter = 0;

final class _SystemFilter implements _SecureFilter {
  final int _number = ++_lastFilter;
  List<_ExternalBuffer>? buffers = [
    for (var i = 0; i < _RawSecureSocket.bufferCount; i++)
      _ExternalBuffer(_RawSecureSocket._isBufferEncrypted(i) ? 10240 : 8192),
  ];
  _Engine? _engine;
  Function? _onComplete;
  bool Function(X509Certificate)? _onBadCertificate;
  bool _isComplete = false;

  _SystemFilter() {
    for (final buffer in buffers!) {
      buffer.data = Uint8List(buffer.size);
    }
    _filters[_number] = this;
  }

  void init() {}

  void connect(
    String hostName,
    SecurityContext context,
    bool isServer,
    bool requestClientCertificate,
    bool requireClientCertificate,
    Uint8List protocols,
  ) {
    _engine = _Engine(
      context as _Context,
      hostName,
      isServer: isServer,
      requestsCertificate: requestClientCertificate,
      requiresCertificate: requireClientCertificate,
      protocols: protocols,
    );
  }

  void destroy() {
    buffers = null;
    _engine?.destroy();
    _engine = null;
    _filters.remove(_number);
  }

  Future<bool> handshake() async {
    final engine = _engine!;
    while (true) {
      switch (engine.handshake()) {
        case _Engine.verifies:
          var isTrusted = engine.isTrusted;
          final certificate = peerCertificate;
          if (!isTrusted && certificate != null) {
            isTrusted = _onBadCertificate?.call(certificate) ?? false;
          }
          if (!isTrusted) {
            throw HandshakeException(
              'Handshake error in ${engine.isServer ? 'server' : 'client'} '
              '(OS Error: \n\tCERTIFICATE_VERIFY_FAILED: ${engine.trustError})',
            );
          }
          engine.trust();
        case _Engine.done:
          if (!_isComplete) {
            _isComplete = true;
            _onComplete?.call();
          }
          return false;
        default:
          return false;
      }
    }
  }

  String? selectedProtocol() => _engine?.selectedProtocol;

  void rehandshake() => throw UnimplementedError();

  X509Certificate? get peerCertificate {
    final der = _engine?.peerCertificate;
    return der == null ? null : _Certificate(der);
  }

  int processBuffer(int bufferIndex) => throw UnimplementedError();

  void registerBadCertificateCallback(
    bool Function(X509Certificate) callback,
  ) => _onBadCertificate = callback;

  void registerHandshakeCompleteCallback(Function handshakeCompleteHandler) =>
      _onComplete = handshakeCompleteHandler;

  void registerKeyLogPort(SendPort port) {}

  void registerKeyLog(void Function(String line) log) {}

  int _pointer() => _number;

  /// Moves what it can between the buffers, which are at [positions], and the
  /// engine, which then are where they are left.
  void _process(List<int> positions, {required bool inHandshake}) {
    final engine = _engine!, all = buffers!;
    int take(int index, int Function(Uint8List data, int at, int count) use) {
      final buffer = all[index], size = buffer.size, data = buffer.data!;
      var start = positions[index * 2];
      final end = positions[index * 2 + 1];
      while (start != end) {
        final count = start > end ? size - start : end - start;
        final used = use(data as Uint8List, start, count);
        if (used <= 0) break;
        start = (start + used) % size;
        if (used < count) break;
      }
      return positions[index * 2] = start;
    }

    int fill(int index, int Function(Uint8List data, int at, int count) put) {
      final buffer = all[index], size = buffer.size, data = buffer.data!;
      final start = positions[index * 2];
      var end = positions[index * 2 + 1];
      while (true) {
        final room = start > end
            ? start - end - 1
            : (start == 0 ? size - 1 : size) - end;
        if (room <= 0) break;
        final count = put(data as Uint8List, end, room);
        if (count <= 0) break;
        end = (end + count) % size;
        if (count < room) break;
      }
      return positions[index * 2 + 1] = end;
    }

    take(_RawSecureSocket.readEncryptedId, engine.feed);
    if (!inHandshake) {
      fill(_RawSecureSocket.readPlaintextId, engine.read);
      take(_RawSecureSocket.writePlaintextId, engine.write);
    }
    fill(_RawSecureSocket.writeEncryptedId, engine.take);
  }
}

/// What the IO service answers for the filter and buffers in [data].
Object _processFilter(List data) {
  final filter = _filters[data[0]];
  final positions = [for (var i = 2; i < data.length; i++) data[i] as int];
  if (filter == null) return [0, 'The filter is gone'];
  try {
    filter._process(positions, inHandshake: data[1] as bool);
  } on TlsException catch (e) {
    return [0, e.message];
  }
  return positions;
}
