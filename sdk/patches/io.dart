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
