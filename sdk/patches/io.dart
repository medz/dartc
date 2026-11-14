import 'dart:ffi' as ffi;

import '../../lib/runtime/contracts.dart';
import '../runtime/memory.dart';

int _exitStatus = 0;

@RuntimeEntry(.processExitCode)
int _readExitCode() => _exitStatus;

@patch
class _ProcessUtils {
  @patch
  static Never _exit(int status) {
    _exitProcess(status);
    throw StateError('Process termination returned');
  }

  @patch
  static void _setExitCode(int status) => _exitStatus = status.toSigned(32);

  @patch
  static int _getExitCode() => _readExitCode();

  @patch
  static void _sleep(int millis) {
    final started = Memory.clock();
    var remaining = millis;
    while (remaining > 0) {
      Memory.sleep(remaining ~/ 1000, remaining % 1000 * 1000000);
      // Signals may end a system wait before the requested duration.
      remaining = millis - (Memory.clock() - started) ~/ 1000000;
    }
  }
}

// FFI represents the non-returning C function with Void, not Dart Never.
@SystemNative()
@ffi.Native<ffi.Void Function(ffi.Int)>(symbol: '_Exit')
external void _exitProcess(int status);

@patch
class _Platform {
  @patch
  static String _operatingSystem() => switch (ffi.Abi.current()) {
    ffi.Abi.macosArm64 || ffi.Abi.macosX64 => 'macos',
    ffi.Abi.linuxArm64 || ffi.Abi.linuxX64 => 'linux',
    final abi => throw UnsupportedError('Platform on $abi'),
  };

  @patch
  static String _pathSeparator() => '/';

  @patch
  static _environment() {
    final table = ffi.DynamicLibrary.process()
        .lookup<ffi.Pointer<ffi.Pointer<ffi.Uint8>>>('environ')
        .value;
    final result = <String>[];
    if (table == ffi.nullptr) return result;
    for (var i = 0; table[i] != ffi.nullptr; i++) {
      final entry = table[i];
      var length = 0;
      while (entry[length] != 0) {
        length++;
      }
      try {
        var text = utf8.decode(entry.asTypedList(length));
        // A leading UTF-8 BOM belongs to the environment name.
        if (length >= 3 &&
            entry[0] == 0xef &&
            entry[1] == 0xbb &&
            entry[2] == 0xbf) {
          text = '\ufeff$text';
        }
        result.add(text);
      } on FormatException {
        // The SDK omits entire environment entries with invalid UTF-8.
      }
    }
    return result;
  }
}

@patch
class _Namespace {
  @patch
  static _Namespace get _namespace => _processNamespace;
}

final _processNamespace = _ProcessNamespace();
final class _ProcessNamespace() extends _Namespace;

@patch
class _Directory {
  @patch
  static _current(_Namespace namespace) {
    final error = _errnoLocation();
    final path = _ioGetcwd(ffi.nullptr, 0);
    if (path == ffi.nullptr) return _ioError(error.value);
    try {
      return _ioString(path);
    } finally {
      _ioFree(path);
    }
  }

  @patch
  static _setCurrent(_Namespace namespace, Uint8List rawPath) {
    final path = _ioMalloc(rawPath.length);
    if (path == ffi.nullptr) throw const OutOfMemoryError();
    try {
      path.asTypedList(rawPath.length).setAll(0, rawPath);
      final error = _errnoLocation();
      return _ioChdir(path) == 0 ? null : _ioError(error.value);
    } finally {
      _ioFree(path);
    }
  }
}

final _errnoLocation = ffi.DynamicLibrary.process()
    .lookupFunction<
      ffi.Pointer<ffi.Int> Function(),
      ffi.Pointer<ffi.Int> Function()
    >(switch (ffi.Abi.current()) {
      ffi.Abi.macosArm64 || ffi.Abi.macosX64 => '__error',
      ffi.Abi.linuxArm64 || ffi.Abi.linuxX64 => '__errno_location',
      final abi => throw UnsupportedError('OS errors on $abi'),
    });

OSError _ioError(int code) => OSError(_ioString(_ioStrerror(code)), code);

String _ioString(ffi.Pointer<ffi.Uint8> pointer) {
  if (pointer == ffi.nullptr) return '';
  var length = 0;
  while (pointer[length] != 0) {
    length++;
  }
  return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
}

@SystemNative()
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'getcwd',
)
external ffi.Pointer<ffi.Uint8> _ioGetcwd(
  ffi.Pointer<ffi.Uint8> buffer,
  int size,
);

@SystemNative()
@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Uint8>)>(symbol: 'chdir')
external int _ioChdir(ffi.Pointer<ffi.Uint8> path);

@SystemNative()
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Int)>(symbol: 'strerror')
external ffi.Pointer<ffi.Uint8> _ioStrerror(int code);

@SystemNative()
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Size)>(symbol: 'malloc')
external ffi.Pointer<ffi.Uint8> _ioMalloc(int size);

@SystemNative()
@ffi.Native<ffi.Void Function(ffi.Pointer<ffi.Uint8>)>(symbol: 'free')
external void _ioFree(ffi.Pointer<ffi.Uint8> pointer);
