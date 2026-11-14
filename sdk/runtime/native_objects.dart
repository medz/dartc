import 'dart:ffi';

import '../../lib/layout/memory.dart' as layout;
import 'heap.dart';
import 'memory.dart';
import 'object_memory.dart';

/// Connects ordinary tracing algorithms to the target's object storage.
final class NativeObjects() implements ObjectAccess {
  @override
  Page? ownerOf(Object value) => Memory.objectAt<Page?>(
    Pointer<Int64>.fromAddress(
      Memory.addressOf(value) + layout.ObjectHeader.pageOffset,
    ).value,
  );

  @override
  int slotOf(Page page, Object value) {
    var offset = Memory.addressOf(value) - page.address;
    if (offset < 0 ||
        offset >= page.slotBytes * page.capacity ||
        offset & (page.slotBytes - 1) != 0) {
      Memory.fail();
    }
    for (var size = page.slotBytes; size > 1; size >>= 1) {
      offset >>= 1;
    }
    return offset;
  }

  @override
  Object objectAt(Page page, int slot) =>
      Memory.objectAt<Object>(page.address + slot * page.slotBytes);

  @override
  void visitStrong(Object value, ReferenceVisitor visitor) {
    final address = Memory.addressOf(value);
    final descriptor = Pointer<Int64>.fromAddress(
      address + layout.ObjectHeader.descriptorOffset,
    ).value;
    final count = Pointer<Int64>.fromAddress(
      descriptor + layout.ObjectDescriptor.referenceCount * 8,
    ).value;
    final bytes = ObjectMemory.size(value);
    for (var i = 0; i < count; i++) {
      final offset = Pointer<Int64>.fromAddress(
        descriptor + (layout.ObjectDescriptor.references + i) * 8,
      ).value;
      if (offset < 0 || offset > bytes - 8 || offset & 7 != 0) Memory.fail();
      visitor.visit(ObjectMemory.reference(address + offset));
    }
    final payload = Pointer<Int64>.fromAddress(
      descriptor + (layout.ObjectDescriptor.payloadBase + count) * 8,
    ).value;
    if (payload == 0) return;
    if (payload < 0 || payload > bytes || payload & 7 != 0) Memory.fail();
    for (var offset = payload; offset < bytes; offset += 8) {
      visitor.visit(ObjectMemory.reference(address + offset));
    }
  }

  @override
  void traceConditional(Object value, Liveness live, ReferenceVisitor visitor) {
    final header = _weakHeader(value);
    final count = Pointer<Int64>.fromAddress(header + 8).value;
    final pairs = header + 16 + Pointer<Int64>.fromAddress(header).value * 8;
    for (var i = 0; i < count; i++) {
      final key = _slotAddress(
        value,
        Pointer<Int64>.fromAddress(pairs + i * 16).value,
      );
      if (live.isAlive(ObjectMemory.reference(key))) {
        final slot = _slotAddress(
          value,
          Pointer<Int64>.fromAddress(pairs + i * 16 + 8).value,
        );
        visitor.visit(ObjectMemory.reference(slot));
      }
    }
  }

  @override
  void clearWeak(Object value, Liveness live) {
    final header = _weakHeader(value);
    final weak = Pointer<Int64>.fromAddress(header).value,
        conditional = Pointer<Int64>.fromAddress(header + 8).value;
    final slots = header + 16;
    for (var i = 0; i < weak; i++) {
      final slot = _slotAddress(
        value,
        Pointer<Int64>.fromAddress(slots + i * 8).value,
      );
      if (!live.isAlive(ObjectMemory.reference(slot))) {
        Pointer<Int64>.fromAddress(slot).value = 0;
      }
    }
    final pairs = slots + weak * 8;
    for (var i = 0; i < conditional; i++) {
      final key = _slotAddress(
        value,
        Pointer<Int64>.fromAddress(pairs + i * 16).value,
      );
      if (live.isAlive(ObjectMemory.reference(key))) continue;
      final slot = _slotAddress(
        value,
        Pointer<Int64>.fromAddress(pairs + i * 16 + 8).value,
      );
      Pointer<Int64>.fromAddress(key).value = 0;
      Pointer<Int64>.fromAddress(slot).value = 0;
    }
  }

  int _weakHeader(Object value) {
    final descriptor = Pointer<Int64>.fromAddress(Memory.addressOf(value))
        .value;
    final strong = Pointer<Int64>.fromAddress(
      descriptor + layout.ObjectDescriptor.referenceCount * 8,
    ).value;
    return descriptor + (layout.ObjectDescriptor.weakCountBase + strong) * 8;
  }

  int _slotAddress(Object value, int offset) {
    if (offset < layout.ObjectHeader.fieldsOffset ||
        offset > ObjectMemory.size(value) - 8 ||
        offset & 7 != 0) {
      Memory.fail();
    }
    return Memory.addressOf(value) + offset;
  }

  @override
  void releasePage(Page page) =>
      Memory.unmap(page.address, page.slotBytes * page.capacity);

  @override
  Never corruptHeap() => Memory.fail();
}
