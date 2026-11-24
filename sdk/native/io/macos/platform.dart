import 'dart:ffi' show DynamicLibrary, DynamicLibraryExtension, Uint8;

@Native<Int64 Function()>(symbol: '_NSGetEnviron')
external int _environmentAddress();

@Native<Int32 Function(Int64, Int64, Int64, Int64, Int64)>(
  symbol: 'sysctlbyname',
)
external int _systemValue(int name, int buffer, int size, int set, int count);

@Native<Int32 Function(Int64, Int64)>(symbol: '_NSGetExecutablePath')
external int _programPath(int buffer, int size);

const _systemName = 'macos', _processorsName = 58;

/// What the system calls [name].
String _systemText(String name) {
  final bytes = FileSystemEntity._toUtf8Array(name);
  store64(_buffer, _bufferBytes - 8);
  final result = _systemValue(dataAddress(bytes), _buffer + 8, _buffer, 0, 0);
  return result < 0 ? '' : _textAt(_buffer + 8);
}

String _systemVersion() =>
    'Version ${_systemText('kern.osproductversion')} '
    '(Build ${_systemText('kern.osversion')})';

/// Where the program is, if that is known.
String? _programFile() {
  store32(_buffer, _bufferBytes - 8);
  return _programPath(_buffer + 8, _buffer) < 0 ? null : _textAt(_buffer + 8);
}

int _environmentStart() => load64(_environmentAddress());

String _language() => _preferredLanguage() ?? 'en-US';

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
