import '../../layout/memory.dart';
import 'memory.dart';
import 'object_memory.dart';
import 'roots.dart';
import 'space.dart';

enum HeapPhase() {
  idle,
  collecting,
  closed,
}

/// Owns the semispaces, roots and lifecycle of a stop-the-world copying heap.
final class CopyingHeap() {
  Space _active = Space();
  Space _spare = Space();
  final RootSlots _roots = RootSlots();
  HeapPhase _phase = .idle;
  int _identityHash = 0;

  /// Allocates initialized storage, returning zero on recoverable exhaustion.
  int allocate(int descriptor, int bytes, int context, int sp, int pc) {
    if (_phase != .idle) Memory.fail();
    var address = _active.reserve(bytes);
    if (address == 0 && _active.start != 0) {
      collect(context, sp, pc);
      address = _active.reserve(bytes);
    }
    if (address == 0) {
      if (!_grow(bytes, context, sp, pc)) return 0;
      address = _active.reserve(bytes);
    }
    _identityHash = (_identityHash + 0x9e3779b9) & 0x3fffffff;
    ObjectMemory.initialize(address, descriptor, bytes, _identityHash);
    return address;
  }

  bool _grow(int bytes, int context, int sp, int pc) {
    final capacity = heapCapacity(_active.capacity, _active.used + bytes);
    if (capacity == 0) return false;
    final first = Memory.map(capacity);
    if (first == 0) return false;
    final second = Memory.map(capacity);
    if (second == 0) {
      Memory.unmap(first, capacity);
      return false;
    }
    final oldStart = _active.start;
    final oldSpare = _spare.start;
    final oldCapacity = _active.capacity;
    _spare.start = first;
    _spare.capacity = capacity;
    collect(context, sp, pc);
    _spare.start = second;
    _spare.capacity = capacity;
    if (oldStart != 0) {
      Memory.unmap(oldStart, oldCapacity);
      Memory.unmap(oldSpare, oldCapacity);
    }
    return true;
  }

  /// Moves live objects and updates every published root before resuming.
  void collect(int context, int sp, int pc) {
    if (_phase != .idle || _spare.capacity < _active.used) Memory.fail();
    _spare.reset();
    _phase = .collecting;
    final holder = Memory.read(context + RuntimeContext.globalRoots);
    if (holder != 0) _trace(Memory.objectAt<Object>(holder));
    _roots.reset(context, sp, pc);
    while (_roots.moveNext()) {
      final slot = _roots.current;
      ObjectMemory.storeReference(slot, _forward(ObjectMemory.reference(slot)));
    }
    while (_spare.scanned < _spare.used) {
      final object = Memory.objectAt<Object>(_spare.start + _spare.scanned);
      _trace(object);
      _spare.scanned += ObjectMemory.size(object);
    }
    final previous = _active;
    _active = _spare;
    _spare = previous;
    _spare.reset();
    _phase = .idle;
  }

  Object? _forward(Object? object) {
    if (object == null) return null;
    if (!_active.contains(Memory.addressOf(object))) return object;
    final address = Memory.addressOf(object);
    final descriptor = Memory.read(address + ObjectHeader.descriptorOffset);
    if (descriptor & 1 != 0) return Memory.objectAt<Object>(descriptor & -2);
    final bytes = ObjectMemory.size(object);
    final destination = _spare.reserve(bytes);
    if (destination == 0) Memory.fail();
    ObjectMemory.copy(destination, object, bytes);
    Memory.write(address + ObjectHeader.descriptorOffset, destination | 1);
    return Memory.objectAt<Object>(destination);
  }

  void _trace(Object object) {
    final address = Memory.addressOf(object);
    final descriptor = Memory.read(address + ObjectHeader.descriptorOffset);
    final references = Memory.read(
      descriptor + ObjectDescriptor.referenceCount * 8,
    );
    for (var i = 0; i < references; i++) {
      final slot =
          address +
          Memory.read(descriptor + (ObjectDescriptor.references + i) * 8);
      ObjectMemory.storeReference(slot, _forward(ObjectMemory.reference(slot)));
    }
    final payload = Memory.read(
      descriptor + (ObjectDescriptor.payloadBase + references) * 8,
    );
    if (payload == 0) return;
    final bytes = ObjectMemory.size(object);
    for (
      var offset = payload;
      offset < bytes;
      offset += ObjectHeader.alignment
    ) {
      final slot = address + offset;
      ObjectMemory.storeReference(slot, _forward(ObjectMemory.reference(slot)));
    }
  }

  void close() {
    if (_phase != .idle) Memory.fail();
    _active.close();
    _spare.close();
    _phase = .closed;
  }
}

/// Enters allocation from a generated constructor with published caller roots.
int allocate(int context, int descriptor, int sp, int pc, int payloadBytes) {
  final prefix = Memory.read(descriptor);
  if (payloadBytes < 0 || payloadBytes > 0x1ffffffffffffff8 - prefix) return 0;
  final bytes = (prefix + payloadBytes + 7) & -8;
  if (Memory.read(context + RuntimeContext.initializing) != 0) {
    final region = Memory.map(bytes + 16);
    if (region == 0) return 0;
    Memory.write(region, Memory.read(context + RuntimeContext.bootstrap));
    Memory.write(region + 8, bytes + 16);
    Memory.write(context + RuntimeContext.bootstrap, region);
    ObjectMemory.initialize(region + 16, descriptor, bytes, 0);
    return region + 16;
  }
  var heap = Memory.objectAt<CopyingHeap?>(
    Memory.read(context + RuntimeContext.heap),
  );
  if (heap == null) {
    Memory.write(context + RuntimeContext.initializing, 1);
    heap = CopyingHeap();
    Memory.write(context + RuntimeContext.heap, Memory.addressOf(heap));
    Memory.write(context + RuntimeContext.initializing, 0);
  }
  return heap.allocate(descriptor, bytes, context, sp, pc);
}

/// Closes the heap and frees all bootstrap objects, including partial startup.
void release(int context) {
  final heap = Memory.objectAt<CopyingHeap?>(
    Memory.read(context + RuntimeContext.heap),
  );
  if (heap != null) heap.close();
  var region = Memory.read(context + RuntimeContext.bootstrap);
  while (region != 0) {
    final next = Memory.read(region);
    Memory.unmap(region, Memory.read(region + 8));
    region = next;
  }
  Memory.write(context + RuntimeContext.heap, 0);
  Memory.write(context + RuntimeContext.bootstrap, 0);
  Memory.write(context + RuntimeContext.initializing, 0);
}
