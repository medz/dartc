// Libraries that programs load.
import 'dart:_heap/machine.dart' show load8, store8;
import 'dart:convert' show utf8;

@Native<Pointer<Void> Function(Pointer<Uint8>, Int32)>(symbol: 'dlopen')
external Pointer<Void> _dlopen(Pointer<Uint8> name, int mode);

@Native<Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>)>(symbol: 'dlsym')
external Pointer<Void> _dlsym(Pointer<Void> library, Pointer<Uint8> name);

@Native<Int32 Function(Pointer<Void>)>(symbol: 'dlclose')
external int _dlclose(Pointer<Void> library);

@Native<Pointer<Uint8> Function()>(symbol: 'dlerror')
external Pointer<Uint8> _dlerror();

@Native<Pointer<Uint8> Function(Size)>(symbol: 'malloc')
external Pointer<Uint8> _mallocBytes(int count);

@Native<Void Function(Pointer<Void>)>(symbol: 'free')
external void _freeBytes(Pointer<Void> address);

/// What [use] gives for [text] as C has it.
R _withText<R>(String text, R Function(Pointer<Uint8> text) use) {
  final bytes = utf8.encode(text);
  final copy = _mallocBytes(bytes.length + 1);
  final start = copy._address;
  for (var i = 0; i < bytes.length; i++) {
    store8(start + i, bytes[i]);
  }
  store8(start + bytes.length, 0);
  try {
    return use(copy);
  } finally {
    _freeBytes(copy.cast());
  }
}

/// The text at [pointer], which a 0 ends.
String _textAt(Pointer<Uint8> pointer) {
  if (pointer._address == 0) return '';
  final bytes = <int>[];
  for (var at = pointer._address; load8(at) != 0; at++) {
    bytes.add(load8(at));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

DynamicLibrary _load(String? path) {
  // Like the official runtime: as needed, and where others do not see it.
  const isLazy = 1;
  final handle = path == null
      ? _dlopen(nullptr, isLazy)
      : _withText(path, (text) => _dlopen(text, isLazy));
  if (handle._address == 0) {
    throw ArgumentError(
      "Failed to load dynamic library '$path': ${_textAt(_dlerror())}",
    );
  }
  return DynamicLibrary._(handle._address);
}

@patch
DynamicLibrary _open(String path) => _load(path);

@patch
DynamicLibrary _processLibrary() => DynamicLibrary._(_anyLibrary);

@patch
DynamicLibrary _executableLibrary() => _load(null);

@patch
DynamicLibrary _codeAsset(String assetId) =>
    throw ArgumentError("No asset with id '$assetId' found.");

@patch
final class DynamicLibrary {
  final int _handle;
  bool _isClosed = false;

  DynamicLibrary._(this._handle);

  void _check() {
    if (_isClosed) throw StateError('Cannot lookup symbols in closed library.');
  }

  Pointer<Void> get _pointer => Pointer<Never>._(_handle);

  @patch
  Pointer<T> lookup<T extends NativeType>(String symbolName) {
    _check();
    final found = _withText(symbolName, (name) => _dlsym(_pointer, name));
    if (found._address == 0) {
      throw ArgumentError(
        "Failed to lookup symbol '$symbolName': ${_textAt(_dlerror())}",
      );
    }
    return Pointer<Never>._(found._address);
  }

  @patch
  bool providesSymbol(String symbolName) {
    _check();
    return _withText(
      symbolName,
      (name) => _dlsym(_pointer, name)._address != 0,
    );
  }

  @patch
  int getHandle() => _handle;

  String toString() => 'DynamicLibrary: handle=${_hex(_handle)}';

  @patch
  void close() {
    if (_isClosed) return;
    _isClosed = true;
    _dlclose(_pointer);
  }
}

/// The address of what is called [symbol] anywhere in the process, which is
/// declared for [asset].
int _resolveNative(String symbol, String asset) {
  final process = DynamicLibrary._(_anyLibrary);
  final found = _withText(symbol, (name) => _dlsym(process._pointer, name));
  if (found._address != 0) return found._address;
  throw ArgumentError(
    "Couldn't resolve native function '$symbol' in '$asset' : "
    "No asset with id '$asset' found. No available native assets. "
    "Attempted to fallback to process lookup. ${_textAt(_dlerror())}.",
  );
}

// Nothing is collected before the program ends.
@patch
void _attachAsTypedListFinalizer(
  Pointer<NativeFinalizerFunction> callback,
  Object typedList,
  Pointer pointer,
  int? externalSize,
) {}
