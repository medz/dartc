// TLS with Secure Transport of the Security framework, whose reads and writes
// go to queues of this program.
import 'dart:ffi'
    show
        DynamicLibrary,
        DynamicLibraryExtension,
        Int32,
        Int64,
        NativeFunctionPointer,
        Pointer,
        Uint8,
        Void;

final _security = DynamicLibrary.open(
  '/System/Library/Frameworks/Security.framework/Security',
);

typedef _I = int Function(int);
typedef _II = int Function(int, int);
typedef _III = int Function(int, int, int);
typedef _IIII = int Function(int, int, int, int);

_I _f1(String name) =>
    _security.lookupFunction<Int64 Function(Int64), _I>(name);
_II _f2(String name) =>
    _security.lookupFunction<Int64 Function(Int64, Int64), _II>(name);
_III _f3(String name) =>
    _security.lookupFunction<Int64 Function(Int64, Int64, Int64), _III>(name);
_IIII _f4(String name) => _security
    .lookupFunction<Int64 Function(Int64, Int64, Int64, Int64), _IIII>(name);

final _createContext = _f3('SSLCreateContext');
final _setIO = _f3('SSLSetIOFuncs');
final _setConnection = _f2('SSLSetConnection');
final _setPeerName = _f3('SSLSetPeerDomainName');
final _setSessionOption = _security
    .lookupFunction<Int32 Function(Int64, Int32, Uint8), _III>(
      'SSLSetSessionOption',
    );
final _setMinimumVersion = _security
    .lookupFunction<Int32 Function(Int64, Int32), _II>(
      'SSLSetProtocolVersionMin',
    );
final _setCertificate = _f2('SSLSetCertificate');
final _setClientAuthentication = _security
    .lookupFunction<Int32 Function(Int64, Int32), _II>(
      'SSLSetClientSideAuthenticate',
    );
final _setProtocols = _f2('SSLSetALPNProtocols');
final _copyProtocols = _f2('SSLCopyALPNProtocols');
final _handshake = _security.lookupFunction<Int32 Function(Int64), _I>(
  'SSLHandshake',
);
final _sslRead = _security
    .lookupFunction<Int32 Function(Int64, Int64, Int64, Int64), _IIII>(
      'SSLRead',
    );
final _sslWrite = _security
    .lookupFunction<Int32 Function(Int64, Int64, Int64, Int64), _IIII>(
      'SSLWrite',
    );
final _copyPeerTrust = _f2('SSLCopyPeerTrust');
final _setPolicies = _f2('SecTrustSetPolicies');
final _sslPolicy = _security.lookupFunction<Int64 Function(Uint8, Int64), _II>(
  'SecPolicyCreateSSL',
);
final _setAnchors = _f2('SecTrustSetAnchorCertificates');
final _setAnchorsOnly = _security
    .lookupFunction<Int32 Function(Int64, Uint8), _II>(
      'SecTrustSetAnchorCertificatesOnly',
    );
final _evaluateTrust = _security
    .lookupFunction<Uint8 Function(Int64, Int64), _II>(
      'SecTrustEvaluateWithError',
    );
final _certificateAt = _f2('SecTrustGetCertificateAtIndex');
final _certificateData = _f1('SecCertificateCopyData');
final _newCertificate = _f2('SecCertificateCreateWithData');
final _newKey = _f3('SecKeyCreateWithData');
final _newIdentity = _f3('SecIdentityCreate');
final _statusText = _f2('SecCopyErrorMessageString');
final _createData = _f3('CFDataCreate');
final _dataLength = _f1('CFDataGetLength');
final _dataBytes = _f1('CFDataGetBytePtr');
final _arrayCount = _f1('CFArrayGetCount');
final _arrayAt = _f2('CFArrayGetValueAtIndex');
final _textBytes = _security
    .lookupFunction<Uint8 Function(Int64, Int64, Int64, Int32), _IIII>(
      'CFStringGetCString',
    );
final _createDictionary = _security
    .lookupFunction<
      Int64 Function(Int64, Int64, Int64, Int64, Int64, Int64),
      int Function(int, int, int, int, int, int)
    >('CFDictionaryCreate');
final _errorDescription = _f1('CFErrorCopyDescription');

int _symbol(String name) => _security.lookup<Void>(name).address;

const _utf8Encoding = 0x08000100, _wouldBlock = -9803, _closed = -9805;
const _peerAuthCompleted = -9841, _certificateRequested = -9842;

/// The engines by the numbers that Secure Transport is given.
final Map<int, _Engine> _engines = {};
int _lastEngine = 0;

final _reads = Pointer.fromFunction<Int32 Function(Int64, Int64, Int64)>(
  _readFor,
  -9806,
);
final _writes = Pointer.fromFunction<Int32 Function(Int64, Int64, Int64)>(
  _writeFor,
  -9806,
);

/// Gives Secure Transport what came from the peer.
int _readFor(int connection, int data, int lengthAt) {
  final engine = _engines[connection]!, wanted = load64(lengthAt);
  final count = min(wanted, engine._input.length - engine._read);
  for (var i = 0; i < count; i++) {
    store8(data + i, engine._input[engine._read + i]);
  }
  engine._read += count;
  store64(lengthAt, count);
  return count < wanted ? _wouldBlock : 0;
}

/// Keeps what Secure Transport has for the peer.
int _writeFor(int connection, int data, int lengthAt) {
  final engine = _engines[connection]!;
  engine._output.addAll(_bytesAt(data, load64(lengthAt)));
  return 0;
}

int _cfText(String text) {
  final bytes = _cString(text);
  final result = _createText(0, bytes, _utf8Encoding);
  _freeBytes(bytes);
  return result;
}

String _textOf(int text) {
  final buffer = _allocateBytes(1024);
  final ok = _textBytes(text, buffer, 1024, _utf8Encoding);
  final result = ok == 0 ? '' : _textAt(buffer);
  _freeBytes(buffer);
  return result;
}

int _cfData(Uint8List bytes) =>
    _createData(0, dataAddress(bytes), bytes.length);

Uint8List _bytesOfData(int data) =>
    _bytesAt(_dataBytes(data), _dataLength(data));

/// A CFArray of [values], which it keeps.
int _cfArray(List<int> values) {
  final at = _allocateBytes(max(values.length, 1) * 8);
  for (final (i, value) in values.indexed) {
    store64(at + i * 8, value);
  }
  final array = _createArray(
    0,
    at,
    values.length,
    _symbol('kCFTypeArrayCallBacks'),
  );
  _freeBytes(at);
  return array;
}

final class _Engine {
  static const done = 0, wants = 1, verifies = 2;

  final int _number = ++_lastEngine;
  final bool isServer, _requiresCertificate;
  final String _host;
  final _Context _context;
  late final int _ssl;
  final List<int> _input = [], _output = [];
  int _read = 0;
  bool isTrusted = false;
  String trustError = '';
  Uint8List? peerCertificate;
  String? selectedProtocol;

  _Engine(
    this._context,
    this._host, {
    required this.isServer,
    required bool requestsCertificate,
    required bool requiresCertificate,
    required Uint8List protocols,
  }) : _requiresCertificate = requiresCertificate {
    _engines[_number] = this;
    _ssl = _createContext(0, isServer ? 0 : 1, 0);
    _setIO(_ssl, _reads.address, _writes.address);
    _setConnection(_ssl, _number);
    _setMinimumVersion(_ssl, 8);
    if (isServer) {
      _useIdentity();
      if (requestsCertificate) {
        _setClientAuthentication(_ssl, requiresCertificate ? 1 : 2);
        _setSessionOption(_ssl, 2, 1);
      }
    } else {
      final name = utf8.encode(_host);
      _setPeerName(_ssl, dataAddress(name), name.length);
      _setSessionOption(_ssl, 0, 1);
    }
    final wanted = protocols.isNotEmpty
        ? protocols
        : (isServer ? _context.serverProtocols : _context.clientProtocols);
    if (wanted != null && wanted.isNotEmpty) {
      final names = [for (final name in _protocolsOf(wanted)) _cfText(name)];
      final array = _cfArray(names);
      _setProtocols(_ssl, array);
      _release(array);
      names.forEach(_release);
    }
  }

  void _useIdentity() {
    final chain = _context.chain, key = _context.key;
    if (chain.isEmpty || key == null) return;
    final rsa = _rsaKey(key);
    if (rsa == null) {
      throw const TlsException('Keys that are not RSA are not supported yet');
    }
    final keys = [_symbol('kSecAttrKeyType'), _symbol('kSecAttrKeyClass')];
    final values = [
      _symbol('kSecAttrKeyTypeRSA'),
      _symbol('kSecAttrKeyClassPrivate'),
    ];
    final keysAt = _allocateBytes(16), valuesAt = _allocateBytes(16);
    for (var i = 0; i < 2; i++) {
      store64(keysAt + i * 8, load64(keys[i]));
      store64(valuesAt + i * 8, load64(values[i]));
    }
    final attributes = _createDictionary(
      0,
      keysAt,
      valuesAt,
      2,
      _symbol('kCFTypeDictionaryKeyCallBacks'),
      _symbol('kCFTypeDictionaryValueCallBacks'),
    );
    _freeBytes(keysAt);
    _freeBytes(valuesAt);
    final keyData = _cfData(rsa);
    final privateKey = _newKey(keyData, attributes, 0);
    _release(keyData);
    _release(attributes);
    if (privateKey == 0) throw const TlsException('Failure in using the key');
    final certificates = [
      for (final der in chain) _newCertificate(0, _cfData(der)),
    ];
    final identity = _newIdentity(0, certificates.first, privateKey);
    if (identity == 0) {
      throw const TlsException('The key is not of the certificate');
    }
    final array = _cfArray([identity, ...certificates.skip(1)]);
    _setCertificate(_ssl, array);
  }

  /// Takes bytes from the peer.
  int feed(Uint8List data, int at, int count) {
    if (_read > 0 && _read == _input.length) {
      _input.clear();
      _read = 0;
    }
    _input.addAll(Uint8List.sublistView(data, at, at + count));
    return count;
  }

  /// Gives bytes for the peer.
  int take(Uint8List data, int at, int count) {
    final given = min(count, _output.length);
    data.setRange(at, at + given, _output);
    _output.removeRange(0, given);
    return given;
  }

  /// Goes on with the handshake: [done], [wants] more input, or [verifies]
  /// the certificate of the peer, which [trust] then lets go on.
  int handshake() {
    while (true) {
      final status = _handshake(_ssl);
      switch (status) {
        case 0:
          _noteProtocol();
          return done;
        case _wouldBlock:
          return wants;
        case _peerAuthCompleted:
          _evaluate();
          return verifies;
        case _certificateRequested:
          continue;
        default:
          throw HandshakeException(
            'Handshake error in ${isServer ? 'server' : 'client'} '
            '(OS Error: \n\t${_messageOf(status)})',
          );
      }
    }
  }

  void trust() {}

  void _evaluate() {
    final place = _allocateBytes(8);
    store64(place, 0);
    _copyPeerTrust(_ssl, place);
    final trust = load64(place);
    if (trust == 0) {
      _freeBytes(place);
      isTrusted = !_requiresCertificate;
      trustError = 'no certificate';
      return;
    }
    final host = isServer ? 0 : _cfText(_host);
    final policy = _sslPolicy(isServer ? 0 : 1, host);
    _setPolicies(trust, policy);
    final anchors = _cfArray([
      for (final der in _context.trusted) _newCertificate(0, _cfData(der)),
    ]);
    if (_context.trusted.isNotEmpty || !_context.trustsRoots) {
      _setAnchors(trust, anchors);
    }
    _setAnchorsOnly(trust, _context.trustsRoots ? 0 : 1);
    store64(place, 0);
    isTrusted = _evaluateTrust(trust, place) != 0;
    final error = load64(place);
    if (error != 0) trustError = _textOf(_errorDescription(error));
    final certificate = _certificateAt(trust, 0);
    if (certificate != 0) {
      peerCertificate = _bytesOfData(_certificateData(certificate));
    }
    _freeBytes(place);
  }

  void _noteProtocol() {
    final place = _allocateBytes(8);
    store64(place, 0);
    _copyProtocols(_ssl, place);
    final array = load64(place);
    _freeBytes(place);
    if (array != 0 && _arrayCount(array) > 0) {
      selectedProtocol = _textOf(_arrayAt(array, 0));
    }
  }

  static String _messageOf(int status) {
    final text = _statusText(status, 0);
    return text == 0 ? 'error $status' : _textOf(text);
  }

  /// Decrypts into [data]. Gives how many bytes.
  int read(Uint8List data, int at, int count) {
    final place = _allocateBytes(8);
    store64(place, 0);
    final status = _sslRead(_ssl, dataAddress(data) + at, count, place);
    final done = load64(place);
    _freeBytes(place);
    if (status != 0 && status != _wouldBlock && status != _closed) {
      throw TlsException(_messageOf(status));
    }
    return done;
  }

  /// Encrypts from [data]. Gives how many bytes it took.
  int write(Uint8List data, int at, int count) {
    final place = _allocateBytes(8);
    store64(place, 0);
    final status = _sslWrite(_ssl, dataAddress(data) + at, count, place);
    final done = load64(place);
    _freeBytes(place);
    if (status != 0 && status != _wouldBlock) {
      throw TlsException(_messageOf(status));
    }
    return done;
  }

  void destroy() {
    _release(_ssl);
    _engines.remove(_number);
  }
}
