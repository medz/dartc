import 'dart:ffi';

import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'heap.dart';
import 'memory.dart';
import 'object_memory.dart';

/// Metadata preceding the initialized objects in a control storage chunk.
abstract final class ControlBlock() {
  static const next = 0;
  static const capacity = 8;
  static const initializedEnd = 16;
  static const headerBytes = 24;
}

/// Allocates permanent control objects without entering the managed heap.
/// Their descriptor references are scanned until [releaseControl] frees them.
@NonAllocating()
int allocateControl(int context, int descriptor, int bytes) {
  final phase = Pointer<Int64>.fromAddress(context + RuntimeContext.phase)
      .value;
  if (phase != RuntimePhase.bootstrap && phase != RuntimePhase.control) {
    Memory.fail();
  }
  if (bytes < ObjectHeader.fieldsOffset || bytes & 7 != 0) Memory.fail();
  var block = Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap)
      .value;
  var cursor = Pointer<Int64>.fromAddress(
    context + RuntimeContext.controlCursor,
  ).value;
  final limit = Pointer<Int64>.fromAddress(
    context + RuntimeContext.controlLimit,
  ).value;
  if (cursor == 0 || bytes > limit - cursor) {
    final capacity = bytes < 65536 - ControlBlock.headerBytes
        ? 65536
        : bytes + ControlBlock.headerBytes;
    final next = Memory.map(capacity);
    if (next == 0) return 0;
    Pointer<Int64>.fromAddress(next + ControlBlock.next).value = block;
    block = next;
    Pointer<Int64>.fromAddress(block + ControlBlock.capacity).value = capacity;
    cursor = block + ControlBlock.headerBytes;
    Pointer<Int64>.fromAddress(block + ControlBlock.initializedEnd).value =
        cursor;
    Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap).value =
        block;
    Pointer<Int64>.fromAddress(context + RuntimeContext.controlLimit).value =
        block + capacity;
  }
  ObjectMemory.initialize(cursor, descriptor, bytes, 0, null);
  Pointer<Int64>.fromAddress(block + ControlBlock.initializedEnd).value =
      cursor + bytes;
  Pointer<Int64>.fromAddress(context + RuntimeContext.controlCursor).value =
      cursor + bytes;
  return cursor;
}

/// Walks only initialized control objects without allocating a traversal stack.
/// All objects remain roots until their context is released, including cycles.
final class ControlObjects(final int context, final ObjectAccess objects) {
  int _block = 0, _next = 0, _end = 0, _address = 0;

  /// The current object's address, or zero before and after traversal.
  int get address => _address;

  void start() {
    _block = Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap)
        .value;
    _next = 0;
    _end = 0;
    _address = 0;
  }

  bool moveNext() {
    while (_block != 0) {
      if (_next == 0) {
        final capacity = Pointer<Int64>.fromAddress(
          _block + ControlBlock.capacity,
        ).value;
        _next = _block + ControlBlock.headerBytes;
        _end = Pointer<Int64>.fromAddress(_block + ControlBlock.initializedEnd)
            .value;
        if (capacity < ControlBlock.headerBytes ||
            capacity & 7 != 0 ||
            _end < _next ||
            _end - _block > capacity ||
            _end & 7 != 0) {
          objects.corruptHeap();
        }
      }
      if (_next == _end) {
        _block = Pointer<Int64>.fromAddress(_block + ControlBlock.next).value;
        _next = 0;
        continue;
      }
      if (_end - _next < ObjectHeader.fieldsOffset) objects.corruptHeap();
      final bytes = Pointer<Int64>.fromAddress(_next + ObjectHeader.sizeOffset)
          .value;
      if (bytes < ObjectHeader.fieldsOffset ||
          bytes & 7 != 0 ||
          bytes > _end - _next ||
          Pointer<Int64>.fromAddress(_next + ObjectHeader.descriptorOffset)
                  .value ==
              0) {
        objects.corruptHeap();
      }
      _address = _next;
      _next += bytes;
      return true;
    }
    _address = 0;
    return false;
  }
}

/// Releases control chunks after the last runtime object has returned.
@NonAllocating()
void releaseControl(int context) {
  final phase = Pointer<Int64>.fromAddress(context + RuntimeContext.phase)
      .value;
  if (phase != RuntimePhase.dormant &&
      phase != RuntimePhase.bootstrap &&
      phase != RuntimePhase.closed) {
    Memory.fail();
  }
  var block = Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap)
      .value;
  while (block != 0) {
    final next = Pointer<Int64>.fromAddress(block + ControlBlock.next).value,
        bytes = Pointer<Int64>.fromAddress(block + ControlBlock.capacity).value;
    Memory.unmap(block, bytes);
    block = next;
  }
  Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.bootstrap).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.controlCursor).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.controlLimit).value = 0;
  Pointer<Int64>.fromAddress(context + RuntimeContext.phase).value =
      RuntimePhase.dormant;
}
