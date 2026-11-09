@DefaultAsset('test:io')
library;

import 'dart:ffi';

import 'package:dartc/interop.dart';

/// Writes up to [count] bytes, returning the byte count or a negative errno.
///
/// Retries interrupted writes only when no bytes were written. Short writes
/// and zero progress are returned to the caller. The caller keeps [bytes]
/// readable for [count] bytes until the operation returns and owns [descriptor].
/// Blocking and signal behavior, including SIGPIPE, follow the descriptor's
/// operating-system contract. This operation does not flush durable storage.
@Export<Int64 Function(Int64, Pointer<Uint8>, Int64)>()
int writeDescriptor(int descriptor, Pointer<Uint8> bytes, int count) {
  if (descriptor < 0 || descriptor > 0x7fffffff) return -_badDescriptor;
  if (count < 0) return -_invalidArgument;
  int result;
  do {
    result = _write(descriptor, bytes, count);
    if (result < 0) result = -_errno().value;
  } while (result == -_interrupted);
  return result;
}

const _interrupted = 4, _badDescriptor = 9, _invalidArgument = 22;

// macOS and Linux LP64 use 64-bit ssize_t/size_t and a 32-bit descriptor.
@Native<Int64 Function(Int32, Pointer<Uint8>, Uint64)>(symbol: 'write')
external int _write(int descriptor, Pointer<Uint8> bytes, int count);

@Native<Pointer<Int32> Function()>(symbol: 'errno', isLeaf: true)
external Pointer<Int32> _errno();
