// Addresses of sockets: as text, as the system has them, and looked up.
import 'dart:_heap/machine.dart' show load16, load32, load64, load8;
import 'dart:_heap/machine.dart' show store16, store32, store64, store8;
import 'dart:ffi' show Int32, Int64, Native, Uint32, Void;

@Native<Int32 Function(Int32, Int64, Int64)>(symbol: 'inet_pton')
external int _textToAddress(int family, int text, int address);

@Native<Int64 Function(Int32, Int64, Int64, Uint32)>(symbol: 'inet_ntop')
external int _addressToText(int family, int address, int text, int size);

@Native<Int32 Function(Int64, Int64, Int64, Int64)>(symbol: 'getaddrinfo')
external int _lookUp(int host, int service, int hints, int result);

@Native<Void Function(Int64)>(symbol: 'freeaddrinfo')
external void _freeLookUp(int result);

@Native<Int64 Function(Int32)>(symbol: 'gai_strerror')
external int _lookUpErrorText(int code);

@Native<Int32 Function(Int64, Uint32, Int64, Uint32, Int64, Uint32, Int32)>(
  symbol: 'getnameinfo',
)
external int _nameOf(
  int address,
  int length,
  int host,
  int hostSize,
  int service,
  int serviceSize,
  int flags,
);

@Native<Int32 Function(Int64)>(symbol: 'getifaddrs')
external int _interfaces(int result);

@Native<Void Function(Int64)>(symbol: 'freeifaddrs')
external void _freeInterfaces(int list);

@Native<Int32 Function(Int64)>(symbol: 'if_nametoindex')
external int _interfaceIndex(int name);

const _afInet = 2, _afUnix = 1, _streamSocket = 1, _datagramSocket = 2;

/// The family of addresses of [raw], which has 4 or 16 bytes.
int _familyOf(Uint8List raw) => raw.length == 4 ? _afInet : _afInet6;

/// [raw] with [port] as the system has it: where and of how many bytes.
(int, int) _socketAddress(Uint8List raw, int port, [int scope = 0]) {
  final isIPv4 = raw.length == 4, length = isIPv4 ? 16 : 28;
  final address = _allocateBytes(length);
  for (var i = 0; i < length; i += 4) {
    store32(address + i, 0);
  }
  _setFamily(address, _familyOf(raw), length);
  store8(address + 2, port >> 8 & 0xff);
  store8(address + 3, port & 0xff);
  final at = address + (isIPv4 ? 4 : 8);
  for (var i = 0; i < raw.length; i++) {
    store8(at + i, raw[i]);
  }
  if (!isIPv4) store32(address + 24, scope);
  return (address, length);
}

/// The address at [address] as its type, text, bytes and port, or null if it
/// is not of the internet.
(int, String, Uint8List, int)? _addressAt(int address) {
  final family = _familyAt(address);
  if (family != _afInet && family != _afInet6) return null;
  final isIPv4 = family == _afInet;
  final raw = _bytesAt(address + (isIPv4 ? 4 : 8), isIPv4 ? 4 : 16);
  final port = load8(address + 2) << 8 | load8(address + 3);
  return (isIPv4 ? 0 : 1, _InternetAddress._rawAddrToString(raw), raw, port);
}

@patch
class _InternetAddress {
  @patch
  static String _rawAddrToString(Uint8List address) {
    final text = _allocateBytes(64);
    final result = _addressToText(
      _familyOf(address),
      dataAddress(address),
      text,
      64,
    );
    final told = result == 0 ? '' : _textAt(text);
    _freeBytes(text);
    return told;
  }

  @patch
  static dynamic _parseScopedLinkLocalAddress(String address) {
    final name = address.substring(address.indexOf('%') + 1);
    final text = _cString(name);
    final index = _interfaceIndex(text);
    _freeBytes(text);
    return index == 0 ? _failure() : index;
  }

  @patch
  static Uint8List? _parse(String address) {
    final text = _cString(address);
    final raw = Uint8List(16);
    Uint8List? found;
    if (_textToAddress(_afInet, text, dataAddress(raw)) == 1) {
      found = raw.sublist(0, 4);
    } else if (_textToAddress(_afInet6, text, dataAddress(raw)) == 1) {
      found = raw;
    }
    _freeBytes(text);
    return found;
  }
}

@patch
class RawSocketOption {
  @patch
  static int _getNativeOptionValue(int key) =>
      [_solSocket, 0, _ipMulticastIf, 41, _ipv6MulticastIf, 6, 17][key];
}

/// The addresses of [host] of [type], as the IO service answers.
Object _lookUpHost(String host, int type) {
  const any = 0;
  final hints = _allocateBytes(48), result = _allocateBytes(8);
  for (var i = 0; i < 48; i += 8) {
    store64(hints + i, 0);
  }
  store32(hints, _lookUpFlags);
  store32(hints + 4, switch (type) {
    0 => _afInet,
    1 => _afInet6,
    _ => any,
  });
  store32(hints + 8, _streamSocket);
  store32(hints + 12, 6);
  final name = _cString(host);
  final code = _lookUp(name, 0, hints, result);
  _freeBytes(name);
  _freeBytes(hints);
  if (code != 0) {
    _freeBytes(result);
    return [_osErrorResponse, code, _textAt(_lookUpErrorText(code))];
  }
  final first = load64(result), found = <Object>[_successResponse];
  _freeBytes(result);
  for (var info = first; info != 0; info = load64(info + _infoNext)) {
    final address = load64(info + _infoAddress);
    if (_addressAt(address) case (final type, final text, final raw, _)?) {
      final scope = type == 1 ? load32(address + 24) : 0;
      found.add([type, text, raw, scope]);
    }
  }
  _freeLookUp(first);
  return found;
}

/// The name of the host at [raw], as the IO service answers.
Object _lookUpName(Uint8List raw) {
  final (address, length) = _socketAddress(raw, 0);
  final host = _allocateBytes(1025);
  final code = _nameOf(address, length, host, 1025, 0, 0, _nameRequired);
  _freeBytes(address);
  final name = code == 0 ? _textAt(host) : null;
  _freeBytes(host);
  return name ?? [_osErrorResponse, code, _textAt(_lookUpErrorText(code))];
}

/// The addresses of the interfaces of [type], as the IO service answers.
Object _listInterfaces(int type) {
  final list = _allocateBytes(8);
  if (_interfaces(list) != 0) {
    _freeBytes(list);
    final error = _failure();
    return [_osErrorResponse, error.errorCode, error.message];
  }
  final first = load64(list), found = <Object>[_successResponse];
  _freeBytes(list);
  for (var at = first; at != 0; at = load64(at)) {
    final address = load64(at + 24), mask = load64(at + 32);
    if (address == 0) continue;
    final told = _addressAt(address);
    if (told == null || type != -1 && told.$1 != type) continue;
    final name = _textAt(load64(at + 8));
    final nameText = _cString(name);
    final index = _interfaceIndex(nameText);
    _freeBytes(nameText);
    var prefix = 0;
    if (mask != 0) {
      final isIPv4 = told.$1 == 0;
      for (final byte in _bytesAt(mask + (isIPv4 ? 4 : 8), isIPv4 ? 4 : 16)) {
        for (var bits = byte; bits != 0; bits &= bits - 1) {
          prefix++;
        }
      }
    }
    found.add([told.$1, told.$2, told.$3, name, index, prefix]);
  }
  _freeInterfaces(first);
  return found;
}
