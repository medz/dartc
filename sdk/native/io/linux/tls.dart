// TLS with the OpenSSL of the system, through buffers in memory.
import 'dart:ffi'
    show
        DynamicLibrary,
        DynamicLibraryExtension,
        Int32,
        Int64,
        NativeFunctionPointer,
        Pointer,
        Void;

final _ssl = DynamicLibrary.open('libssl.so.3');
final _crypto = DynamicLibrary.open('libcrypto.so.3');

typedef _I = int Function(int);
typedef _II = int Function(int, int);
typedef _III = int Function(int, int, int);
typedef _IIII = int Function(int, int, int, int);

_I _s1(String name, [DynamicLibrary? from]) =>
    (from ?? _ssl).lookupFunction<Int64 Function(Int64), _I>(name);
_II _s2(String name, [DynamicLibrary? from]) =>
    (from ?? _ssl).lookupFunction<Int64 Function(Int64, Int64), _II>(name);
_III _s3(String name, [DynamicLibrary? from]) => (from ?? _ssl)
    .lookupFunction<Int64 Function(Int64, Int64, Int64), _III>(name);
_IIII _s4(String name, [DynamicLibrary? from]) => (from ?? _ssl)
    .lookupFunction<Int64 Function(Int64, Int64, Int64, Int64), _IIII>(name);

final _method = _ssl.lookupFunction<Int64 Function(), int Function()>(
  'TLS_method',
);
final _newContext = _s1('SSL_CTX_new');
final _freeContext = _s1('SSL_CTX_free');
final _contextControl = _s4('SSL_CTX_ctrl');
final _defaultPaths = _s1('SSL_CTX_set_default_verify_paths');
final _store = _s1('SSL_CTX_get_cert_store');
final _addToStore = _s2('X509_STORE_add_cert', _crypto);
final _readCertificate = _s3('d2i_X509', _crypto);
final _writeCertificate = _s2('i2d_X509', _crypto);
final _freeCertificate = _s1('X509_free', _crypto);
final _readKey = _s3('d2i_AutoPrivateKey', _crypto);
final _useCertificate = _s2('SSL_CTX_use_certificate');
final _useKey = _s2('SSL_CTX_use_PrivateKey');
final _setSelect = _s3('SSL_CTX_set_alpn_select_cb');
final _newSsl = _s1('SSL_new');
final _freeSsl = _s1('SSL_free');
final _memory = _ssl.lookupFunction<Int64 Function(), int Function()>(
  'BIO_s_mem',
);
final _newBio = _s1('BIO_new', _crypto);
final _setBio = _s3('SSL_set_bio');
final _connectState = _s1('SSL_set_connect_state');
final _acceptState = _s1('SSL_set_accept_state');
final _sslControl = _s4('SSL_ctrl');
final _parameters = _s1('SSL_get0_param');
final _setHost = _s3('X509_VERIFY_PARAM_set1_host', _crypto);
final _setIp = _s2('X509_VERIFY_PARAM_set1_ip_asc', _crypto);
final _setVerify = _ssl
    .lookupFunction<
      Void Function(Int64, Int32, Int64),
      void Function(int, int, int)
    >('SSL_set_verify');
final _doHandshake = _ssl.lookupFunction<Int32 Function(Int64), _I>(
  'SSL_do_handshake',
);
final _sslError = _ssl.lookupFunction<Int32 Function(Int64, Int32), _II>(
  'SSL_get_error',
);
final _nextError = _crypto.lookupFunction<Int64 Function(), int Function()>(
  'ERR_get_error',
);
final _errorString = _crypto
    .lookupFunction<
      Void Function(Int64, Int64, Int64),
      void Function(int, int, int)
    >('ERR_error_string_n');
final _bioWrite = _crypto
    .lookupFunction<Int32 Function(Int64, Int64, Int32), _III>('BIO_write');
final _bioRead = _crypto
    .lookupFunction<Int32 Function(Int64, Int64, Int32), _III>('BIO_read');
final _sslRead = _ssl.lookupFunction<Int32 Function(Int64, Int64, Int32), _III>(
  'SSL_read',
);
final _sslWrite = _ssl
    .lookupFunction<Int32 Function(Int64, Int64, Int32), _III>('SSL_write');
final _verifyResult = _s1('SSL_get_verify_result');
final _verifyText = _s1('X509_verify_cert_error_string', _crypto);
final _peer = _s1('SSL_get1_peer_certificate');
final _selected = _s3('SSL_get0_alpn_selected');
final _setProtocols = _ssl
    .lookupFunction<Int32 Function(Int64, Int64, Int32), _III>(
      'SSL_set_alpn_protos',
    );
final _selectNext = _ssl
    .lookupFunction<
      Int32 Function(Int64, Int64, Int64, Int32, Int64, Int32),
      int Function(int, int, int, int, int, int)
    >('SSL_select_next_proto');

/// The engines by the numbers that OpenSSL is given.
final Map<int, _Engine> _engines = {};
int _lastEngine = 0;

final _accepts = Pointer.fromFunction<Int32 Function(Int32, Int64)>(
  _acceptAll,
  0,
);

/// Lets certificates that are not trusted be decided after the handshake.
int _acceptAll(int ok, int context) => 1;

final _selects =
    Pointer.fromFunction<
      Int32 Function(Int64, Int64, Int64, Int64, Int32, Int64)
    >(_selectFor, 3);

/// Picks the protocol of the server that the client offers too.
int _selectFor(int ssl, int out, int length, int given, int count, int arg) {
  final engine = _engines[arg];
  final (protocols, size) = engine?._serverProtocols ?? (0, 0);
  if (protocols == 0) return 3;
  final found = _selectNext(out, length, protocols, size, given, count);
  return found == 1 ? 0 : 3;
}

/// A copy of [bytes] outside the heap.
int _copyOut(Uint8List bytes) {
  final at = _allocateBytes(max(bytes.length, 1));
  for (var i = 0; i < bytes.length; i++) {
    store8(at + i, bytes[i]);
  }
  return at;
}

final class _Engine {
  static const done = 0, wants = 1, verifies = 2;

  final int _number = ++_lastEngine;
  final bool isServer, _checks, _requiresCertificate;
  late final int _context, _connection, _input, _output;
  (int, int)? _serverProtocols;
  bool _isChecked = false;
  bool isTrusted = false;
  String trustError = '';
  Uint8List? peerCertificate;
  String? selectedProtocol;

  _Engine(
    _Context context,
    String host, {
    required this.isServer,
    required bool requestsCertificate,
    required bool requiresCertificate,
    required Uint8List protocols,
  }) : _checks = !isServer || requestsCertificate,
       _requiresCertificate = requiresCertificate {
    _engines[_number] = this;
    _context = _newContext(_method());
    _contextControl(_context, 123, 0x0303, 0);
    if (context.trustsRoots) _defaultPaths(_context);
    for (final der in context.trusted) {
      final certificate = _certificateOf(der);
      _addToStore(_store(_context), certificate);
      _freeCertificate(certificate);
    }
    if (context.chain case [final first, ...final rest]) {
      _useCertificate(_context, _certificateOf(first));
      for (final der in rest) {
        _contextControl(_context, 89, 0, _certificateOf(der));
      }
    }
    if (context.key case final key?) {
      final place = _allocateBytes(8), bytes = _copyOut(key);
      store64(place, bytes);
      final privateKey = _readKey(0, place, key.length);
      _freeBytes(place);
      _freeBytes(bytes);
      if (privateKey == 0 || _useKey(_context, privateKey) != 1) {
        throw TlsException('Failure in using the key', _osErrorOf());
      }
    }
    final wanted = protocols.isNotEmpty
        ? protocols
        : (isServer ? context.serverProtocols : context.clientProtocols);
    if (isServer && wanted != null && wanted.isNotEmpty) {
      _serverProtocols = (_copyOut(wanted), wanted.length);
      _setSelect(_context, _selects.address, _number);
    }
    _connection = _newSsl(_context);
    _input = _newBio(_memory());
    _output = _newBio(_memory());
    _setBio(_connection, _input, _output);
    if (isServer) {
      _acceptState(_connection);
      if (requestsCertificate) {
        _setVerify(_connection, requiresCertificate ? 3 : 1, _accepts.address);
      }
    } else {
      _connectState(_connection);
      final name = _cString(host);
      if (InternetAddress.tryParse(host) == null) {
        _sslControl(_connection, 55, 0, name);
        _setHost(_parameters(_connection), name, 0);
      } else {
        _setIp(_parameters(_connection), name);
      }
      _freeBytes(name);
      _setVerify(_connection, 0, 0);
      if (wanted != null && wanted.isNotEmpty) {
        final bytes = _copyOut(wanted);
        _setProtocols(_connection, bytes, wanted.length);
        _freeBytes(bytes);
      }
    }
  }

  static int _certificateOf(Uint8List der) {
    final place = _allocateBytes(8), bytes = _copyOut(der);
    store64(place, bytes);
    final certificate = _readCertificate(0, place, der.length);
    _freeBytes(place);
    _freeBytes(bytes);
    if (certificate == 0) {
      throw TlsException('Failure in parsing a certificate', _osErrorOf());
    }
    return certificate;
  }

  /// The errors of OpenSSL so far, as one.
  static OSError _osErrorOf() {
    final text = StringBuffer(), buffer = _allocateBytes(256);
    var code = 0;
    for (var error = _nextError(); error != 0; error = _nextError()) {
      code = error;
      _errorString(error, buffer, 256);
      text.write(_textAt(buffer));
    }
    _freeBytes(buffer);
    return OSError('$text', code);
  }

  int feed(Uint8List data, int at, int count) =>
      max(0, _bioWrite(_input, dataAddress(data) + at, count));

  int take(Uint8List data, int at, int count) =>
      max(0, _bioRead(_output, dataAddress(data) + at, count));

  /// Goes on with the handshake: [done], [wants] more input, or [verifies]
  /// the certificate of the peer, which [trust] then lets go on.
  int handshake() {
    final result = _doHandshake(_connection);
    if (result != 1) {
      final error = _sslError(_connection, result);
      if (error == 2 || error == 3) return wants;
      throw HandshakeException(
        'Handshake error in ${isServer ? 'server' : 'client'}',
        _osErrorOf(),
      );
    }
    if (_checks && !_isChecked) {
      _isChecked = true;
      _check();
      return verifies;
    }
    _noteProtocol();
    return done;
  }

  void trust() {}

  void _check() {
    final certificate = _peer(_connection);
    if (certificate == 0) {
      isTrusted = !_requiresCertificate;
      trustError = 'no certificate';
      return;
    }
    final length = _writeCertificate(certificate, 0);
    final bytes = _allocateBytes(length), place = _allocateBytes(8);
    store64(place, bytes);
    _writeCertificate(certificate, place);
    peerCertificate = _bytesAt(bytes, length);
    _freeBytes(bytes);
    _freeBytes(place);
    _freeCertificate(certificate);
    final result = _verifyResult(_connection);
    isTrusted = result == 0;
    trustError = _textAt(_verifyText(result));
  }

  void _noteProtocol() {
    final place = _allocateBytes(16);
    store64(place, 0);
    store64(place + 8, 0);
    _selected(_connection, place, place + 8);
    final data = load64(place), length = load32(place + 8);
    if (data != 0 && length > 0) {
      selectedProtocol = latin1.decode(_bytesAt(data, length));
    }
    _freeBytes(place);
  }

  int read(Uint8List data, int at, int count) {
    final result = _sslRead(_connection, dataAddress(data) + at, count);
    if (result > 0) return result;
    final error = _sslError(_connection, result);
    // Wanting more, and the end that the peer tells, are no errors.
    if (error == 2 || error == 3 || error == 6) return 0;
    throw TlsException('Failure in reading', _osErrorOf());
  }

  int write(Uint8List data, int at, int count) {
    final result = _sslWrite(_connection, dataAddress(data) + at, count);
    if (result > 0) return result;
    final error = _sslError(_connection, result);
    if (error == 2 || error == 3) return 0;
    throw TlsException('Failure in writing', _osErrorOf());
  }

  void destroy() {
    _freeSsl(_connection);
    _freeContext(_context);
    if (_serverProtocols case (final at, _)) _freeBytes(at);
    _engines.remove(_number);
  }
}
