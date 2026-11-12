import '../../lib/layout/memory.dart';
import 'memory.dart';

/// Interprets object storage shared by the compiler and collector.
abstract final class ObjectMemory() {
  static int size(Object object) =>
      Memory.read(Memory.addressOf(object) + ObjectHeader.sizeOffset);

  static Object? reference(int slot) =>
      Memory.objectAt<Object?>(Memory.read(slot));

  static void storeReference(int slot, Object? value) =>
      Memory.write(slot, Memory.addressOf(value));

  static void initialize(
    int address,
    int descriptor,
    int size,
    int hash,
    Object? page,
  ) {
    for (var offset = 0; offset < size; offset += ObjectHeader.alignment) {
      Memory.write(address + offset, 0);
    }
    Memory.write(address + ObjectHeader.descriptorOffset, descriptor);
    Memory.write(address + ObjectHeader.sizeOffset, size);
    Memory.write(address + ObjectHeader.identityHashOffset, hash);
    storeReference(address + ObjectHeader.pageOffset, page);
  }
}
