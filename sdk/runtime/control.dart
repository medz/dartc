import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'memory.dart';
import 'object_memory.dart';

/// Allocates control objects in reusable chunks without entering the user heap.
@NonAllocating()
int allocateControl(int context, int descriptor, int bytes) {
  var cursor = Memory.read(context + RuntimeContext.controlCursor);
  final limit = Memory.read(context + RuntimeContext.controlLimit);
  if (cursor == 0 || bytes > limit - cursor) {
    final capacity = bytes < 65520 ? 65536 : bytes + 16;
    final block = Memory.map(capacity);
    if (block == 0) return 0;
    Memory.write(block, Memory.read(context + RuntimeContext.bootstrap));
    Memory.write(block + 8, capacity);
    Memory.write(context + RuntimeContext.bootstrap, block);
    cursor = block + 16;
    Memory.write(context + RuntimeContext.controlLimit, block + capacity);
  }
  Memory.write(context + RuntimeContext.controlCursor, cursor + bytes);
  ObjectMemory.initialize(cursor, descriptor, bytes, 0, null);
  return cursor;
}

/// Releases control chunks after the last runtime object has returned.
@NonAllocating()
void releaseControl(int context) {
  var block = Memory.read(context + RuntimeContext.bootstrap);
  while (block != 0) {
    final next = Memory.read(block), bytes = Memory.read(block + 8);
    Memory.unmap(block, bytes);
    block = next;
  }
  Memory.write(context + RuntimeContext.heap, 0);
  Memory.write(context + RuntimeContext.bootstrap, 0);
  Memory.write(context + RuntimeContext.controlCursor, 0);
  Memory.write(context + RuntimeContext.controlLimit, 0);
  Memory.write(context + RuntimeContext.initializing, 0);
}
