import 'dart:convert';

import '../../lib/runtime/contracts.dart';

@patch
DynamicLibrary _open(String path) =>
    _withLibraryString(path, (name) => _loadLibrary(name, true));

@patch
DynamicLibrary _processLibrary() => DynamicLibrary._(
  Pointer.fromAddress(switch (Abi.current()) {
    Abi.macosArm64 || Abi.macosX64 => -2,
    Abi.linuxArm64 || Abi.linuxX64 => 0,
    _ => throw UnsupportedError('Dynamic libraries on ${Abi.current()}'),
  }),
  false,
);

@patch
DynamicLibrary _executableLibrary() => _loadLibrary(nullptr, false);

DynamicLibrary _loadLibrary(Pointer<Uint8> name, bool canClose) {
  final handle = _dlopen(name, 1); // RTLD_LAZY on supported POSIX targets.
  if (handle == nullptr) throw ArgumentError(_libraryError());
  try {
    return DynamicLibrary._(handle, canClose);
  } catch (_) {
    _dlclose(handle);
    rethrow;
  }
}

@patch
class DynamicLibrary {
  final Pointer<Void> _handle;
  final bool _canClose;
  bool _closed = false;

  DynamicLibrary._(this._handle, this._canClose);

  @patch
  Pointer<T> lookup<T extends NativeType>(String symbolName) {
    final (address, error) = _lookup(symbolName);
    if (error != null) throw ArgumentError(error);
    return address.cast<T>();
  }

  @patch
  bool providesSymbol(String symbolName) => _lookup(symbolName).$2 == null;

  (Pointer<Void>, String?) _lookup(String symbolName) {
    if (_closed) throw StateError('Dynamic library is closed.');
    return _withLibraryString(symbolName, (name) {
      _dlerror();
      final address = _dlsym(_handle, name);
      // A null symbol address is valid; only dlerror identifies a failed lookup.
      return (address, _libraryError());
    });
  }

  @patch
  void close() {
    if (_closed) return;
    if (!_canClose) {
      throw StateError('Process and executable libraries cannot be closed.');
    }
    if (_dlclose(_handle) != 0)
      throw StateError(_libraryError() ?? 'dlclose failed');
    _closed = true;
  }
}

// The official Dart bodies use this VM helper; keep it private to dart:ffi.
extension _DynamicLibraryHandle on DynamicLibrary {
  int getHandle() => _handle.address;
}

T _withLibraryString<T>(String value, T Function(Pointer<Uint8>) action) {
  if (value.contains('\u0000')) throw ArgumentError.value(value, 'name');
  final bytes = utf8.encode(value);
  final storage = _dlMalloc(bytes.length + 1);
  if (storage == nullptr) throw const OutOfMemoryError();
  try {
    for (var i = 0; i < bytes.length; i++) {
      storage[i] = bytes[i];
    }
    storage[bytes.length] = 0;
    return action(storage);
  } finally {
    _dlFree(storage);
  }
}

String? _libraryError() {
  final message = _dlerror();
  if (message == nullptr) return null;
  final bytes = <int>[];
  for (var i = 0; message[i] != 0; i++) {
    bytes.add(message[i]);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

@SystemNative(library: .dynamicLoader)
@Native<Pointer<Void> Function(Pointer<Uint8>, Int)>(symbol: 'dlopen')
external Pointer<Void> _dlopen(Pointer<Uint8> path, int flags);

@SystemNative(library: .dynamicLoader)
@Native<Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>)>(symbol: 'dlsym')
external Pointer<Void> _dlsym(Pointer<Void> handle, Pointer<Uint8> name);

@SystemNative(library: .dynamicLoader)
@Native<Int Function(Pointer<Void>)>(symbol: 'dlclose')
external int _dlclose(Pointer<Void> handle);

@SystemNative(library: .dynamicLoader)
@Native<Pointer<Uint8> Function()>(symbol: 'dlerror')
external Pointer<Uint8> _dlerror();

@SystemNative()
@Native<Pointer<Uint8> Function(Size)>(symbol: 'malloc')
external Pointer<Uint8> _dlMalloc(int size);

@SystemNative()
@Native<Void Function(Pointer<Uint8>)>(symbol: 'free')
external void _dlFree(Pointer<Uint8> pointer);
