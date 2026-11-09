import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

final _system = DynamicLibrary.process();
final _allocate = _system
    .lookupFunction<
      Pointer<Uint8> Function(Size),
      Pointer<Uint8> Function(int)
    >('malloc');
final _free = _system
    .lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)
    >('free');
final _chmod = Platform.isMacOS
    ? _system.lookupFunction<
        Int32 Function(Pointer<Uint8>, Uint16),
        int Function(Pointer<Uint8>, int)
      >('chmod')
    : _system.lookupFunction<
        Int32 Function(Pointer<Uint8>, Uint32),
        int Function(Pointer<Uint8>, int)
      >('chmod');
final _errno = _system
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );

/// Adds execute permission wherever the staged output is readable.
void makeExecutable(File file) {
  final bytes = utf8.encode(file.absolute.path);
  final path = _allocate(bytes.length + 1);
  if (path == nullptr) {
    throw FileSystemException('Cannot allocate file path', file.path);
  }
  try {
    path.asTypedList(bytes.length + 1)
      ..setAll(0, bytes)
      ..[bytes.length] = 0;
    final mode = file.statSync().mode & 0x1ff;
    final errno = _errno();
    if (_chmod(path, mode | (mode & 0x124) >> 2) != 0) {
      final error = errno.value;
      throw FileSystemException(
        'Cannot make output executable',
        file.path,
        OSError('chmod failed', error),
      );
    }
  } finally {
    _free(path);
  }
}
