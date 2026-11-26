// Certificates and keys: PEM, the parts of DER that are told, and SHA-1, the
// same on all systems.

/// The DER of each block of [label]s in the PEM [text], or of [text] itself
/// if it is not PEM.
List<Uint8List> _derBlocks(List<int> text, List<String> labels) {
  final string = latin1.decode(text, allowInvalid: true);
  if (!string.contains('-----BEGIN ')) return [Uint8List.fromList(text)];
  final found = <Uint8List>[];
  final block = RegExp(r'-----BEGIN ([A-Z0-9 ]+)-----([^-]*)-----END \1-----');
  for (final match in block.allMatches(string)) {
    if (!labels.contains(match[1])) continue;
    found.add(base64.decode(match[2]!.replaceAll(RegExp(r'\s'), '')));
  }
  if (found.isEmpty) {
    throw const TlsException('Failure in parsing a certificate or key');
  }
  return found;
}

const _certificateLabels = ['CERTIFICATE', 'TRUSTED CERTIFICATE'];
const _keyLabels = ['PRIVATE KEY', 'RSA PRIVATE KEY', 'EC PRIVATE KEY'];

/// A part of DER: its tag and where its content is in [bytes].
final class _Der {
  final Uint8List bytes;
  final int tag, start, end;
  _Der(this.bytes, this.tag, this.start, this.end);

  /// The part at [at] in [bytes].
  factory _Der.at(Uint8List bytes, int at) {
    final tag = bytes[at];
    var length = bytes[at + 1], start = at + 2;
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      length = 0;
      for (var i = 0; i < count; i++) {
        length = length << 8 | bytes[start++];
      }
    }
    return _Der(bytes, tag, start, start + length);
  }

  /// The parts that it holds.
  List<_Der> get parts {
    final found = <_Der>[];
    for (var at = start; at < end;) {
      final part = _Der.at(bytes, at);
      found.add(part);
      at = part.end;
    }
    return found;
  }

  Uint8List get content => Uint8List.sublistView(bytes, start, end);
}

/// Names of attributes of names, as the official runtime tells them.
const _attributeNames = {
  '2.5.4.3': 'CN',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '1.2.840.113549.1.9.1': 'emailAddress',
};

String _objectId(Uint8List bytes) {
  final numbers = [bytes[0] ~/ 40, bytes[0] % 40];
  var value = 0;
  for (final byte in bytes.skip(1)) {
    value = value << 7 | byte & 0x7f;
    if (byte & 0x80 == 0) {
      numbers.add(value);
      value = 0;
    }
  }
  return numbers.join('.');
}

/// A name in the one-line form: `/CN=localhost`.
String _nameText(_Der name) => [
  for (final set in name.parts)
    for (final pair in set.parts)
      '/${_attributeNames[_objectId(pair.parts[0].content)] ?? _objectId(pair.parts[0].content)}'
          '=${utf8.decode(pair.parts[1].content, allowMalformed: true)}',
].join();

DateTime _time(_Der time) {
  var text = ascii.decode(time.content);
  // A two-digit year is of 1950 to 2049.
  if (time.tag == 0x17) {
    text = '${int.parse(text.substring(0, 2)) < 50 ? '20' : '19'}$text';
  }
  return DateTime.utc(
    int.parse(text.substring(0, 4)),
    int.parse(text.substring(4, 6)),
    int.parse(text.substring(6, 8)),
    int.parse(text.substring(8, 10)),
    int.parse(text.substring(10, 12)),
    int.parse(text.substring(12, 14)),
  );
}

final class _Certificate implements X509Certificate {
  final Uint8List der;
  late final _Der _signed = _Der.at(der, 0).parts[0];

  /// The parts of what is signed, without the version if it is there.
  late final List<_Der> _fields = [
    for (final part in _signed.parts)
      if (part.tag != 0xa0) part,
  ];

  _Certificate(this.der);

  String get pem {
    final text = base64.encode(der);
    final lines = [
      for (var at = 0; at < text.length; at += 64)
        text.substring(at, min(at + 64, text.length)),
    ];
    return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
        '-----END CERTIFICATE-----\n';
  }

  Uint8List get sha1 => _sha1(der);
  String get issuer => _nameText(_fields[2]);
  String get subject => _nameText(_fields[4]);
  DateTime get startValidity => _time(_fields[3].parts[0]);
  DateTime get endValidity => _time(_fields[3].parts[1]);
}

/// The RSA key in [key], which can be PKCS #8, as PKCS #1, or null if it is
/// of another kind.
Uint8List? _rsaKey(Uint8List key) {
  final parts = _Der.at(key, 0).parts;
  // PKCS #1 starts with a version and the modulus.
  if (parts.length > 3 && parts[1].tag == 0x02) return key;
  const rsa = '1.2.840.113549.1.1.1';
  final algorithm = parts[1].parts[0].content;
  return _objectId(algorithm) == rsa ? parts[2].content : null;
}

Uint8List _sha1(Uint8List data) {
  final length = data.length, padded = ((length + 8) ~/ 64 + 1) * 64;
  final message = Uint8List(padded)
    ..setRange(0, length, data)
    ..[length] = 0x80;
  final bits = length * 8;
  for (var i = 0; i < 8; i++) {
    message[padded - 1 - i] = bits >> (8 * i) & 0xff;
  }
  var h = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0];
  final w = List.filled(80, 0);
  int rotate(int x, int n) => (x << n | x >> (32 - n)) & 0xffffffff;
  for (var chunk = 0; chunk < padded; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      final at = chunk + i * 4;
      w[i] =
          message[at] << 24 |
          message[at + 1] << 16 |
          message[at + 2] << 8 |
          message[at + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var [a, b, c, d, e] = h;
    for (var i = 0; i < 80; i++) {
      final (f, k) = i < 20
          ? ((b & c) | (~b & d), 0x5a827999)
          : i < 40
          ? (b ^ c ^ d, 0x6ed9eba1)
          : i < 60
          ? ((b & c) | (b & d) | (c & d), 0x8f1bbcdc)
          : (b ^ c ^ d, 0xca62c1d6);
      final next =
          (rotate(a, 5) + (f & 0xffffffff) + e + k + w[i]) & 0xffffffff;
      e = d;
      d = c;
      c = rotate(b, 30);
      b = a;
      a = next;
    }
    h = [
      for (final (i, value) in [a, b, c, d, e].indexed)
        (h[i] + value) & 0xffffffff,
    ];
  }
  return Uint8List.fromList([
    for (final word in h) ...[
      word >> 24,
      word >> 16 & 0xff,
      word >> 8 & 0xff,
      word & 0xff,
    ],
  ]);
}

/// What secure sockets are given: trusted certificates, the chain and key of
/// this side, and what it does with protocols and versions.
final class _Context implements SecurityContext {
  final bool trustsRoots;
  final List<Uint8List> trusted = [], chain = [], authorities = [];
  Uint8List? key;
  Uint8List? serverProtocols, clientProtocols;
  bool allowLegacyUnsafeRenegotiation = false;
  TlsProtocolVersion minimumTlsProtocolVersion = TlsProtocolVersion.tls1_2;

  _Context(this.trustsRoots);

  static final SecurityContext defaultContext = _Context(true);

  static Uint8List _bytes(String file) => File(file).readAsBytesSync();

  void usePrivateKey(String file, {String? password}) =>
      usePrivateKeyBytes(_bytes(file), password: password);

  void usePrivateKeyBytes(List<int> keyBytes, {String? password}) {
    if (password != null) {
      throw const TlsException('Keys with passwords are not supported yet');
    }
    key = _derBlocks(keyBytes, _keyLabels).first;
  }

  void setTrustedCertificates(String file, {String? password}) =>
      setTrustedCertificatesBytes(_bytes(file), password: password);

  void setTrustedCertificatesBytes(List<int> certBytes, {String? password}) =>
      trusted.addAll(_derBlocks(certBytes, _certificateLabels));

  void useCertificateChain(String file, {String? password}) =>
      useCertificateChainBytes(_bytes(file), password: password);

  void useCertificateChainBytes(List<int> chainBytes, {String? password}) {
    chain
      ..clear()
      ..addAll(_derBlocks(chainBytes, _certificateLabels));
  }

  void setClientAuthorities(String file, {String? password}) =>
      setClientAuthoritiesBytes(_bytes(file), password: password);

  void setClientAuthoritiesBytes(List<int> authCertBytes, {String? password}) =>
      authorities.addAll(_derBlocks(authCertBytes, _certificateLabels));

  void setAlpnProtocols(List<String> protocols, bool isServer) {
    final encoded = SecurityContext._protocolsToLengthEncoding(protocols);
    if (isServer) {
      serverProtocols = encoded;
    } else {
      clientProtocols = encoded;
    }
  }
}

/// The protocols in the [encoded] list of lengths and names.
List<String> _protocolsOf(Uint8List encoded) => [
  for (var at = 0; at < encoded.length; at += 1 + encoded[at])
    latin1.decode(encoded.sublist(at + 1, at + 1 + encoded[at])),
];
