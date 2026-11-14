import 'dart:ffi' as ffi;

import '../../lib/runtime/contracts.dart';
import '../runtime/memory.dart';

int _exitStatus = 0;

@RuntimeEntry(.processExitCode)
int _readExitCode() => _exitStatus;

@patch
class _ProcessUtils {
  @patch
  static int _pid(Process? process) {
    if (process != null) {
      throw UnsupportedError('Child process handles are not implemented.');
    }
    return _ioGetpid();
  }

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
  static int _numberOfProcessors() {
    if (_operatingSystem() == 'linux')
      return _ioSysconf(84); // _SC_NPROCESSORS_ONLN
    final value = _ioMalloc(4);
    if (value == ffi.nullptr) throw const OutOfMemoryError();
    try {
      final length = _ioMalloc(ffi.sizeOf<ffi.Size>());
      if (length == ffi.nullptr) throw const OutOfMemoryError();
      try {
        final name = _ioMalloc(14);
        if (name == ffi.nullptr) throw const OutOfMemoryError();
        try {
          name.asTypedList(14).setAll(0, utf8.encode('hw.logicalcpu\u0000'));
          final size = length.cast<ffi.Size>()..value = 4;
          final query = ffi.DynamicLibrary.process()
              .lookupFunction<
                ffi.Int Function(
                  ffi.Pointer<ffi.Uint8>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Size>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Size,
                ),
                int Function(
                  ffi.Pointer<ffi.Uint8>,
                  ffi.Pointer<ffi.Void>,
                  ffi.Pointer<ffi.Size>,
                  ffi.Pointer<ffi.Void>,
                  int,
                )
              >('sysctlbyname', isLeaf: true);
          if (query(name, value.cast(), size, ffi.nullptr, 0) == 0) {
            return value.cast<ffi.Int32>().value;
          }
        } finally {
          _ioFree(name);
        }
      } finally {
        _ioFree(length);
      }
    } finally {
      _ioFree(value);
    }
    return _ioSysconf(58); // Darwin's _SC_NPROCESSORS_ONLN.
  }

  @patch
  static _localHostname() {
    final buffer = _ioMalloc(256);
    if (buffer == ffi.nullptr) throw const OutOfMemoryError();
    try {
      final error = _errnoLocation();
      if (_ioGethostname(buffer, 256) != 0) return _ioError(error.value);
      buffer[255] = 0;
      return _ioString(buffer);
    } finally {
      _ioFree(buffer);
    }
  }

  @patch
  static _resolvedExecutable() {
    if (_operatingSystem() == 'linux') {
      final path = Uint8List.fromList(utf8.encode('/proc/self/exe\u0000'));
      for (var size = 256; ; size *= 2) {
        final buffer = _ioMalloc(size + 1);
        if (buffer == ffi.nullptr) throw const OutOfMemoryError();
        try {
          final error = _errnoLocation();
          final length = _ioReadlink(path.address, buffer, size);
          if (length < 0) throw _ioError(error.value);
          if (length < size) {
            buffer[length] = 0;
            return _ioString(buffer);
          }
        } finally {
          _ioFree(buffer);
        }
      }
    }
    final query = ffi.DynamicLibrary.process()
        .lookupFunction<
          ffi.Int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint32>),
          int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint32>)
        >('_NSGetExecutablePath', isLeaf: true);
    final length = _ioMalloc(4);
    if (length == ffi.nullptr) throw const OutOfMemoryError();
    try {
      final size = length.cast<ffi.Uint32>()..value = 0;
      query(ffi.nullptr, size);
      if (size.value == 0)
        throw const OSError('Executable path is unavailable');
      final buffer = _ioMalloc(size.value);
      if (buffer == ffi.nullptr) throw const OutOfMemoryError();
      try {
        if (query(buffer, size) != 0) {
          throw const OSError('Executable path changed during resolution');
        }
        final error = _errnoLocation();
        final path = _ioRealpath(buffer, ffi.nullptr);
        if (path == ffi.nullptr) throw _ioError(error.value);
        try {
          return _ioString(path);
        } finally {
          _ioFree(path);
        }
      } finally {
        _ioFree(buffer);
      }
    } finally {
      _ioFree(length);
    }
  }

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
  static String _systemTemp(_Namespace namespace) {
    final storage = _ioMalloc(7);
    if (storage == ffi.nullptr) throw const OutOfMemoryError();
    try {
      final name = storage.asTypedList(7);
      for (final variable in ['TMPDIR', 'TMP']) {
        name.setAll(0, '$variable\u0000'.codeUnits);
        final value = _ioGetenv(storage);
        if (value != ffi.nullptr) {
          final path = _ioString(value);
          return path.length > 1 && path.endsWith('/')
              ? path.substring(0, path.length - 1)
              : path;
        }
      }
      return '/tmp';
    } finally {
      _ioFree(storage);
    }
  }

  @patch
  static _createTemp(_Namespace namespace, Uint8List rawPath) {
    final length = rawPath.indexOf(0);
    final path = _ioMalloc(length + 7);
    if (path == ffi.nullptr) throw const OutOfMemoryError();
    try {
      final buffer = path.asTypedList(length + 7);
      buffer.setRange(0, length, rawPath);
      final error = _errnoLocation();
      while (true) {
        buffer.setAll(length, 'XXXXXX\u0000'.codeUnits);
        final result = _ioMkdtemp(path);
        if (result != ffi.nullptr) return _ioString(result);
        final code = error.value;
        if (code != 4) return _ioError(code); // Retry EINTR on POSIX targets.
      }
    } finally {
      _ioFree(path);
    }
  }

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

@patch
abstract class FileSystemEntity {
  @patch
  static _resolveSymbolicLinks(_Namespace namespace, Uint8List path) {
    final input = _ioMalloc(path.length);
    if (input == ffi.nullptr) throw const OutOfMemoryError();
    try {
      input.asTypedList(path.length).setAll(0, path);
      final error = _errnoLocation();
      ffi.Pointer<ffi.Uint8> resolved;
      do {
        resolved = _ioRealpath(input, ffi.nullptr);
      } while (resolved == ffi.nullptr && error.value == 4);
      if (resolved == ffi.nullptr) return _ioError(error.value);
      try {
        return _ioString(resolved);
      } finally {
        _ioFree(resolved);
      }
    } finally {
      _ioFree(input);
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
  final bytes = pointer.asTypedList(length);
  final text = utf8.decode(bytes, allowMalformed: true);
  // OS strings treat a leading BOM as data, unlike the UTF-8 decoder.
  return length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf
      ? '\ufeff$text'
      : text;
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

@SystemNative()
@ffi.Native<ffi.Int Function()>(symbol: 'getpid', isLeaf: true)
external int _ioGetpid();

@SystemNative()
@ffi.Native<ffi.Long Function(ffi.Int)>(symbol: 'sysconf', isLeaf: true)
external int _ioSysconf(int name);

@SystemNative()
@ffi.Native<ffi.Int Function(ffi.Pointer<ffi.Uint8>, ffi.Size)>(
  symbol: 'gethostname',
  isLeaf: true,
)
external int _ioGethostname(ffi.Pointer<ffi.Uint8> buffer, int length);

@SystemNative()
@ffi.Native<
  ffi.IntPtr Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>, ffi.Size)
>(symbol: 'readlink', isLeaf: true)
external int _ioReadlink(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Pointer<ffi.Uint8> buffer,
  int size,
);

// glibc's compatibility realpath rejects null; dlsym selects the default version.
final _ioRealpath = ffi.DynamicLibrary.process()
    .lookupFunction<
      ffi.Pointer<ffi.Uint8> Function(
        ffi.Pointer<ffi.Uint8>,
        ffi.Pointer<ffi.Uint8>,
      ),
      ffi.Pointer<ffi.Uint8> Function(
        ffi.Pointer<ffi.Uint8>,
        ffi.Pointer<ffi.Uint8>,
      )
    >('realpath');

@SystemNative()
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Uint8>)>(
  symbol: 'getenv',
)
external ffi.Pointer<ffi.Uint8> _ioGetenv(ffi.Pointer<ffi.Uint8> name);

@SystemNative()
@ffi.Native<ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Uint8>)>(
  symbol: 'mkdtemp',
)
external ffi.Pointer<ffi.Uint8> _ioMkdtemp(ffi.Pointer<ffi.Uint8> template);
