import 'dart:ffi';

import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Interprets object storage shared by the compiler and collector.
abstract final class ObjectMemory() {
  static int size(Object object) => Pointer<Int64>.fromAddress(
    Memory.addressOf(object) + ObjectHeader.sizeOffset,
  ).value;

  static Object? reference(int slot) =>
      Memory.objectAt<Object?>(Pointer<Int64>.fromAddress(slot).value);

  static void storeReference(int slot, Object? value) {
    Pointer<Int64>.fromAddress(slot).value = Memory.addressOf(value);
  }

  static void initialize(
    int address,
    int descriptor,
    int size,
    int hash,
    Object? page,
  ) {
    for (var offset = 0; offset < size; offset += ObjectHeader.alignment) {
      Pointer<Int64>.fromAddress(address + offset).value = 0;
    }
    Pointer<Int64>.fromAddress(address + ObjectHeader.descriptorOffset).value =
        descriptor;
    Pointer<Int64>.fromAddress(address + ObjectHeader.sizeOffset).value = size;
    Pointer<Int64>.fromAddress(address + ObjectHeader.identityHashOffset)
            .value =
        hash;
    storeReference(address + ObjectHeader.pageOffset, page);
  }
}
