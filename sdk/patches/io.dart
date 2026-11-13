import 'dart:ffi' as ffi;

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
