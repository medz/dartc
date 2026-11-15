import 'dart:ffi';
import 'dart:typed_data';

int zeroByte(int index) {
  if (index < 0 || index >= 16) return -1;
  return Uint8List(16)[index];
}

int dartAttached(Finalizer<int> finalizer, int token) {
  final bytes = Uint8List(16);
  finalizer.attach(bytes, token);
  return bytes[0];
}

final class Resource(final Uint8List bytes) implements Finalizable;

int nativeAttached(NativeFinalizer finalizer) {
  final resource = Resource(Uint8List(16));
  finalizer.attach(resource, Pointer<Void>.fromAddress(1));
  return resource.bytes[0];
}
