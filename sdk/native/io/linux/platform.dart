@Native<Int32 Function(Int64)>(symbol: 'uname')
external int _systemNames(int result);

@Native<Int64 Function(Int64, Int64)>(symbol: 'dlsym')
external int _symbolAddress(int library, int name);

const _systemName = 'linux', _processorsName = 84;

String _systemVersion() {
  // Each name has as many bytes.
  const bytes = 65, system = 0, release = 2, version = 3;
  if (_systemNames(_buffer) < 0) return '';
  String name(int index) => _textAt(_buffer + index * bytes);
  return '${name(system)} ${name(release)} ${name(version)}';
}

/// Where the program is, if that is known.
String? _programFile() {
  final link = FileSystemEntity._toUtf8Array('/proc/self/exe');
  final length = _readLink(dataAddress(link), _buffer, _bufferBytes);
  return length < 0
      ? null
      : utf8.decode(_bytesAt(_buffer, length), allowMalformed: true);
}

int _environmentStart() {
  final name = FileSystemEntity._toUtf8Array('environ');
  return load64(_symbolAddress(0, dataAddress(name)));
}

String _language() => Platform.environment['LANG'] ?? 'en_US';
