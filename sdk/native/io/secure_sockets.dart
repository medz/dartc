// Secure sockets, whose filter calls the key log itself instead of a port.
// TLS itself is not there yet.

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
  factory _SecureFilter._() => throw UnsupportedError(_noTls);

  /// Tells [log] the lines of the key log.
  void registerKeyLog(void Function(String line) log);
}

@patch
base class _SecureFilterImpl {
  void registerKeyLog(void Function(String line) log) {}
}

const _noTls = 'Secure sockets are not supported yet.';

/// What would be the port of the key log, which there never is.
final class _NoPort {
  void close() {}
}

@patch
class SecurityContext {
  @patch
  factory SecurityContext({bool withTrustedRoots = false}) =>
      throw UnsupportedError(_noTls);

  @patch
  static SecurityContext get defaultContext => throw UnsupportedError(_noTls);
}

@patch
class X509Certificate {
  @patch
  factory X509Certificate._() => throw UnsupportedError(_noTls);
}
