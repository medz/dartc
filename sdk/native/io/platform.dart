import 'dart:_heap/objects.dart' show arguments;

@Native<Int64 Function(Int32)>(symbol: 'sysconf')
external int _systemNumber(int name);

@Native<Int32 Function(Int64, Int64)>(symbol: 'gethostname')
external int _hostName(int buffer, int size);

@patch
class _Platform {
  @patch
  static int _numberOfProcessors() => _systemNumber(_processorsName);

  @patch
  static String _pathSeparator() => '/';

  @patch
  static String _operatingSystem() => _systemName;

  @patch
  static _operatingSystemVersion() => _systemVersion();

  @patch
  static _localHostname() =>
      _hostName(_buffer, _bufferBytes) < 0 ? _failure() : _textAt(_buffer);

  @patch
  static _executable() => _textAt(load64(load64(arguments() + 8)));

  @patch
  static _resolvedExecutable() {
    final path = _programFile();
    if (path == null) return _executable();
    final bytes = FileSystemEntity._toUtf8Array(path);
    return _realPath(dataAddress(bytes), _buffer) == 0
        ? _executable()
        : _textAt(_buffer);
  }

  @patch
  static _environment() {
    final result = <String>[];
    for (var at = _environmentStart(); load64(at) != 0; at += 8) {
      result.add(_textAt(load64(at)));
    }
    return result;
  }

  @patch
  static List<String> _executableArguments() => const [];

  @patch
  static String _version() => '3.14.0 (dartc) on "$_targetName"';

  @patch
  static Uri _script() {
    final path = _programFile();
    if (path == null) return Uri();
    return Uri.file(File(path).absolute.path).normalizePath();
  }

  @patch
  static String? _packageConfig() => null;

  @patch
  static String _localeName() => _language();
}

// Texts of the system are UTF-8 here.
@patch
class _WindowsCodePageDecoder {
  @patch
  static String _decodeBytes(List<int> bytes) =>
      throw UnsupportedError('This is for Windows only.');
}

@patch
class _WindowsCodePageEncoder {
  @patch
  static List<int> _encodeString(String string) =>
      throw UnsupportedError('This is for Windows only.');
}
