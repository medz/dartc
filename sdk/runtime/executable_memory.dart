import 'dart:ffi';

import '../../lib/runtime/contracts.dart';
import 'memory.dart';

/// Makes a fresh executable mapping without requiring unsigned-code privileges.
@RuntimeEntry(.copyExecutableMacos)
bool copyExecutableMacos(int destination, int source, int bytes) {
  final scratch = Memory.map(32);
  if (scratch == 0) return false;
  try {
    final address = Pointer<UintPtr>.fromAddress(scratch)..value = destination;
    final current = Pointer<Int32>.fromAddress(scratch + 8);
    final maximum = Pointer<Int32>.fromAddress(scratch + 12);
    final task = _machTaskSelf();
    return _vmRemap(
              task,
              address,
              bytes,
              0,
              0x4000,
              task,
              source,
              1,
              current,
              maximum,
              2,
            ) ==
            0 &&
        address.value == destination;
  } finally {
    Memory.unmap(scratch, 32);
  }
}

/// Copies into writable storage, then removes write access before publication.
@RuntimeEntry(.copyExecutableLinux)
bool copyExecutableLinux(int destination, int source, int bytes) {
  Memory.copyBytes(destination, source, bytes);
  if (_protect(Pointer.fromAddress(destination), bytes, 5) != 0) return false;
  Memory.flushInstructions(destination, bytes);
  return true;
}

@SystemNative()
@Native<Uint32 Function()>(symbol: 'mach_task_self', isLeaf: true)
external int _machTaskSelf();

@SystemNative()
@Native<
  Int32 Function(
    Uint32,
    Pointer<UintPtr>,
    UintPtr,
    UintPtr,
    Int32,
    Uint32,
    UintPtr,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
  )
>(symbol: 'vm_remap')
external int _vmRemap(
  int task,
  Pointer<UintPtr> address,
  int bytes,
  int mask,
  int flags,
  int sourceTask,
  int source,
  int copy,
  Pointer<Int32> current,
  Pointer<Int32> maximum,
  int inheritance,
);

@SystemNative()
@Native<Int Function(Pointer<Void>, Size, Int)>(symbol: 'mprotect')
external int _protect(Pointer<Void> address, int bytes, int protection);
