import 'dart:ffi';

import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'memory.dart';
import 'object_memory.dart';

/// Allocates control objects in reusable chunks without entering the user heap.
@NonAllocating()
int allocateControl(int context, int descriptor, int bytes) {
  var cursor = Pointer<Int64>.fromAddress(
    context + RuntimeContext.controlCursor,
  ).value;
  final limit = Pointer<Int64>.fromAddress(
    context + RuntimeContext.controlLimit,
  ).value;
  if (cursor == 0 || bytes > limit - cursor) {
    final capacity = bytes < 65520 ? 65536 : bytes + 16;
    final block = Memory.map(capacity);
    if (block == 0) return 0;
    Pointer<Int64>.fromAddress(block)
        .value = Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap)
        .value;
    Pointer<Int64>.fromAddress(block + 8).value = capacity;
    Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap).value =
        block;
    cursor = block + 16;
    Pointer<Int64>.fromAddress(context + RuntimeContext.controlLimit).value =
        block + capacity;
  }
  Pointer<Int64>.fromAddress(context + RuntimeContext.controlCursor).value =
      cursor + bytes;
  ObjectMemory.initialize(cursor, descriptor, bytes, 0, null);
  return cursor;
}

/// Releases control chunks after the last runtime object has returned.
@NonAllocating()
void releaseControl(int context) {
  var block = Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap)
      .value;
  while (block != 0) {
    final next = Pointer<Int64>.fromAddress(block).value,
        bytes = Pointer<Int64>.fromAddress(block + 8).value;
    Memory.unmap(block, bytes);
    block = next;
  }
  Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.controlCursor).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.controlLimit).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.initializing).value = 0;
}
