import '../../lib/layout/memory.dart' as layout;
import 'heap.dart';
import 'memory.dart';
import 'object_memory.dart';

/// Connects ordinary tracing algorithms to the target's object storage.
final class NativeObjects() implements ObjectAccess {
  @override
  Page? ownerOf(Object value) => Memory.objectAt<Page?>(
    Memory.read(Memory.addressOf(value) + layout.ObjectHeader.pageOffset),
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
    final descriptor = Memory.read(
      address + layout.ObjectHeader.descriptorOffset,
    );
    final count = Memory.read(
      descriptor + layout.ObjectDescriptor.referenceCount * 8,
    );
    final bytes = ObjectMemory.size(value);
    for (var i = 0; i < count; i++) {
      final offset = Memory.read(
        descriptor + (layout.ObjectDescriptor.references + i) * 8,
      );
      if (offset < 0 || offset > bytes - 8 || offset & 7 != 0) Memory.fail();
      visitor.visit(ObjectMemory.reference(address + offset));
    }
    final payload = Memory.read(
      descriptor + (layout.ObjectDescriptor.payloadBase + count) * 8,
    );
    if (payload == 0) return;
    if (payload < 0 || payload > bytes || payload & 7 != 0) Memory.fail();
    for (var offset = payload; offset < bytes; offset += 8) {
      visitor.visit(ObjectMemory.reference(address + offset));
    }
  }

  @override
  void traceConditional(Object value, Liveness live, ReferenceVisitor visitor) {
    final header = _weakHeader(value);
    final count = Memory.read(header + 8);
    final pairs = header + 16 + Memory.read(header) * 8;
    for (var i = 0; i < count; i++) {
      final key = _slotAddress(value, Memory.read(pairs + i * 16));
      if (live.isAlive(ObjectMemory.reference(key))) {
        final slot = _slotAddress(value, Memory.read(pairs + i * 16 + 8));
        visitor.visit(ObjectMemory.reference(slot));
      }
    }
  }

  @override
  void clearWeak(Object value, Liveness live) {
    final header = _weakHeader(value);
    final weak = Memory.read(header), conditional = Memory.read(header + 8);
    final slots = header + 16;
    for (var i = 0; i < weak; i++) {
      final slot = _slotAddress(value, Memory.read(slots + i * 8));
      if (!live.isAlive(ObjectMemory.reference(slot))) Memory.write(slot, 0);
    }
    final pairs = slots + weak * 8;
    for (var i = 0; i < conditional; i++) {
      final key = _slotAddress(value, Memory.read(pairs + i * 16));
      if (live.isAlive(ObjectMemory.reference(key))) continue;
      final slot = _slotAddress(value, Memory.read(pairs + i * 16 + 8));
      Memory.write(key, 0);
      Memory.write(slot, 0);
    }
  }

  int _weakHeader(Object value) {
    final descriptor = Memory.read(Memory.addressOf(value));
    final strong = Memory.read(
      descriptor + layout.ObjectDescriptor.referenceCount * 8,
    );
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
