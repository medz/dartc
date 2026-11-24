import 'dart:_heap/objects.dart' show arguments;
import 'dart:ffi' show DynamicLibrary, DynamicLibraryExtension, Uint32, Uint8;

@Native<Int64 Function()>(symbol: '_NSGetEnviron')
external int _environmentAddress();

@Native<Int64 Function(Int32)>(symbol: 'sysconf')
external int _systemNumber(int name);

@Native<Int32 Function(Int64, Int64)>(symbol: 'gethostname')
external int _hostName(int buffer, int size);

@Native<Int32 Function(Int64, Int64, Int64, Int64, Int64)>(
  symbol: 'sysctlbyname',
)
external int _systemValue(int name, int buffer, int size, int set, int count);

@Native<Int32 Function(Int64, Int64)>(symbol: '_NSGetExecutablePath')
external int _programPath(int buffer, int size);

/// What the system calls [name].
String _systemText(String name) {
  final bytes = FileSystemEntity._toUtf8Array(name);
  store64(_buffer, _bufferBytes - 8);
  final result = _systemValue(dataAddress(bytes), _buffer + 8, _buffer, 0, 0);
  return result < 0 ? '' : _textAt(_buffer + 8);
}

@patch
class _Platform {
  @patch
  static int _numberOfProcessors() => _systemNumber(58);

  @patch
  static String _pathSeparator() => '/';

  @patch
  static String _operatingSystem() => 'macos';

  @patch
  static _operatingSystemVersion() =>
      'Version ${_systemText('kern.osproductversion')} '
      '(Build ${_systemText('kern.osversion')})';

  @patch
  static _localHostname() =>
      _hostName(_buffer, _bufferBytes) < 0 ? _failure() : _textAt(_buffer);

  @patch
  static _executable() => _textAt(load64(load64(arguments() + 8)));

  @patch
  static _resolvedExecutable() {
    store32(_buffer, _bufferBytes - 8);
    if (_programPath(_buffer + 8, _buffer) < 0) return _executable();
    final path = FileSystemEntity._toUtf8Array(_textAt(_buffer + 8));
    return _realPath(dataAddress(path), _buffer) == 0
        ? _executable()
        : _textAt(_buffer);
  }

  @patch
  static _environment() {
    final result = <String>[];
    for (var at = load64(_environmentAddress()); load64(at) != 0; at += 8) {
      result.add(_textAt(load64(at)));
    }
    return result;
  }

  @patch
  static List<String> _executableArguments() => const [];

  @patch
  static String _version() => '3.14.0 (dartc) on "macos_arm64"';

  @patch
  static Uri _script() {
    store32(_buffer, _bufferBytes - 8);
    if (_programPath(_buffer + 8, _buffer) < 0) return Uri();
    return Uri.file(File(_textAt(_buffer + 8)).absolute.path).normalizePath();
  }

  @patch
  static String? _packageConfig() => null;

  @patch
  static String _localeName() => _preferredLanguage() ?? 'en-US';
}

/// The first language that the user wants, if that is known.
String? _preferredLanguage() {
  const path =
      '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation';
  const isUtf8 = 0x08000100;
  final library = DynamicLibrary.open(path);
  final languages = library.lookupFunction<Int64 Function(), int Function()>(
    'CFLocaleCopyPreferredLanguages',
  )();
  if (languages == 0) return null;
  final count = library
      .lookupFunction<Int64 Function(Int64), int Function(int)>(
        'CFArrayGetCount',
      )(languages);
  if (count == 0) return null;
  final first = library
      .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
        'CFArrayGetValueAtIndex',
      )(languages, 0);
  final result = library
      .lookupFunction<
        Uint8 Function(Int64, Int64, Int64, Uint32),
        int Function(int, int, int, int)
      >('CFStringGetCString')(first, _buffer, _bufferBytes, isUtf8);
  return result == 0 ? null : _textAt(_buffer);
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
