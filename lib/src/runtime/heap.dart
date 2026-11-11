import 'contracts.dart';

enum HeapPhase() {
  running,
  marking,
  weakProcessing,
  sweeping,
  closed,
}

/// Receives strong references without invoking application code.
abstract interface class ReferenceVisitor() {
  void visit(Object? value);
}

/// Answers reachability queries during collection.
abstract interface class Liveness() {
  bool isAlive(Object? value);
}

/// Publishes roots while application execution is stopped.
abstract interface class RootSet() {
  bool stop();
  void visit(ReferenceVisitor visitor);
  void resume();
  void close();
}

/// Reads validated object storage without allocating or invoking getters.
abstract interface class ObjectAccess() {
  Page? ownerOf(Object value);
  int slotOf(Page page, Object value);
  Object objectAt(Page page, int slot);
  void visitStrong(Object value, ReferenceVisitor visitor);
  void traceConditional(Object value, Liveness live, ReferenceVisitor visitor);
  void clearWeak(Object value, Liveness live);
  void releasePage(Page page);
  Never corruptHeap();
}

/// Stages existing finalization records without running their callbacks.
abstract interface class Finalization() {
  void visitPending(ReferenceVisitor visitor);
  void stage(Liveness live);
  void finishShutdown();
}

/// Tracks fixed-size object slots and tracing work in one storage region.
final class Page(
  final ObjectAccess objects,
  int address,
  int slotBytes,
  int capacity,
) {
  int _address = address, _slotBytes = slotBytes, _capacity = capacity;
  int get address => _address;
  int get slotBytes => _slotBytes;
  int get capacity => _capacity;
  Heap? _owner;
  Page? _next;
  Page? _pendingNext;
  bool _queued = false;
  int _allocated = 0;
  int _marked = 0;
  int _pending = 0;
  int _cursor = 0;
  int _freeCursor = 0;

  /// Reuses empty metadata after replacement storage has been acquired.
  void replaceStorage(int address, int slotBytes, int capacity) {
    if (_owner?.phase != .running ||
        _allocated != 0 ||
        address == 0 ||
        slotBytes <= 0 ||
        slotBytes & (slotBytes - 1) != 0 ||
        capacity < 1 ||
        capacity > 64) {
      objects.corruptHeap();
    }
    objects.releasePage(this);
    _address = address;
    _slotBytes = slotBytes;
    _capacity = capacity;
    _freeCursor = 0;
  }

  /// The number of occupied slots.
  int get used {
    var count = 0;
    for (var bits = _allocated; bits != 0; bits &= bits - 1) {
      count++;
    }
    return count;
  }

  /// Reserves one slot, or returns -1 without changing a full page.
  int reserve() {
    if (_owner?.phase != .running) objects.corruptHeap();
    for (var slot = _freeCursor; slot < capacity; slot++) {
      final bit = 1 << (slot & 63);
      if (_allocated & bit != 0) continue;
      _allocated |= bit;
      _freeCursor = slot + 1;
      return slot;
    }
    return -1;
  }

  bool _mark(Object value) {
    final slot = _slot(value), bit = 1 << (slot & 63);
    if (_marked & bit != 0) return false;
    _marked |= bit;
    _pending |= bit;
    if (slot < _cursor) _cursor = slot;
    return true;
  }

  int _slot(Object value) {
    final slot = objects.slotOf(this, value);
    if (slot < 0 || slot >= capacity || _allocated & (1 << (slot & 63)) == 0) {
      objects.corruptHeap();
    }
    return slot;
  }

  Object? _takePending() {
    if (_pending == 0) return null;
    while (_cursor < capacity) {
      final slot = _cursor++, bit = 1 << (slot & 63);
      if (_pending & bit == 0) continue;
      _pending &= ~bit;
      return objects.objectAt(this, slot);
    }
    objects.corruptHeap();
  }

  void _sweep() {
    _allocated &= _marked;
    _marked = 0;
    _pending = 0;
    _cursor = 0;
    _freeCursor = 0;
  }
}

/// Owns a precise non-moving heap and its collection lifecycle.
final class Heap(
  final ObjectAccess objects,
  final RootSet roots,
  final Finalization finalization,
) implements ReferenceVisitor, Liveness {
  Page? _pages;
  Page? _head;
  Page? _tail;
  HeapPhase _phase = .running;
  int _markedCount = 0;

  /// The current collection or shutdown phase.
  HeapPhase get phase => _phase;

  /// Occupied storage after the most recent sweep, including slot padding.
  int get liveBytes {
    var bytes = 0;
    for (var page = _pages; page != null; page = page._next) {
      bytes += page.used * page.slotBytes;
    }
    return bytes;
  }

  /// Empty metadata available for a different size class.
  Page? get emptyPage {
    for (var page = _pages; page != null; page = page._next) {
      if (page._allocated == 0) return page;
    }
    return null;
  }

  /// Adds initialized page metadata before any slots are reserved.
  void addPage(Page page) {
    if (_phase != .running ||
        !identical(page.objects, objects) ||
        page._owner != null ||
        page.capacity < 1 ||
        page.capacity > 64 ||
        page.slotBytes <= 0 ||
        page.slotBytes & (page.slotBytes - 1) != 0) {
      objects.corruptHeap();
    }
    page._owner = this;
    page._next = _pages;
    _pages = page;
  }

  /// Finds reusable storage in a page of the requested size class.
  Page? availablePage(int slotBytes) {
    if (_phase != .running) objects.corruptHeap();
    Page? previous;
    for (var page = _pages; page != null; page = page._next) {
      final full = page.capacity == 64 ? -1 : (1 << (page.capacity & 63)) - 1;
      if (page.slotBytes == slotBytes && page._allocated != full) {
        if (previous != null) {
          previous._next = page._next;
          page._next = _pages;
          _pages = page;
        }
        return page;
      }
      previous = page;
    }
    return null;
  }

  @override
  void visit(Object? value) {
    if (_phase != .marking && _phase != .weakProcessing) {
      objects.corruptHeap();
    }
    if (value == null) return;
    final page = objects.ownerOf(value);
    if (page == null) return;
    if (page._owner != this) objects.corruptHeap();
    if (!page._mark(value)) return;
    _markedCount++;
    if (page._queued) return;
    page._queued = true;
    if (_tail case final tail?) {
      tail._pendingNext = page;
    } else {
      _head = page;
    }
    _tail = page;
  }

  @override
  bool isAlive(Object? value) {
    if (_phase != .marking && _phase != .weakProcessing) {
      objects.corruptHeap();
    }
    if (value == null) return false;
    final page = objects.ownerOf(value);
    if (page == null) return true;
    if (page._owner != this) objects.corruptHeap();
    return page._marked & (1 << (page._slot(value) & 63)) != 0;
  }

  /// Collects published roots, or returns false if stopping was deferred.
  bool collect() {
    if (_phase != .running) objects.corruptHeap();
    if (!roots.stop()) return false;
    _collectStopped();
    roots.resume();
    return true;
  }

  @NonAllocating()
  void _collectStopped() {
    _phase = .marking;
    _markedCount = 0;
    roots.visit(this);
    finalization.visitPending(this);
    _drain();
    _phase = .weakProcessing;
    _closeEphemerons();
    finalization.stage(this);
    _clearWeakReferences();
    _phase = .sweeping;
    for (var page = _pages; page != null; page = page._next) {
      page._sweep();
    }
    _phase = .running;
  }

  void _drain() {
    for (var page = _head; page != null; page = _head) {
      final object = page._takePending();
      if (object == null) {
        _head = page._pendingNext;
        if (_head == null) _tail = null;
        page._pendingNext = null;
        page._queued = false;
      } else {
        objects.visitStrong(object, this);
      }
    }
  }

  void _closeEphemerons() {
    int before;
    do {
      before = _markedCount;
      for (var page = _pages; page != null; page = page._next) {
        for (var slot = 0; slot < page.capacity; slot++) {
          if (page._marked & (1 << (slot & 63)) == 0) continue;
          final object = objects.objectAt(page, slot);
          objects.traceConditional(object, this, this);
        }
      }
      _drain();
    } while (_markedCount != before);
  }

  void _clearWeakReferences() {
    for (var page = _pages; page != null; page = page._next) {
      for (var slot = 0; slot < page.capacity; slot++) {
        if (page._marked & (1 << (slot & 63)) == 0) continue;
        final object = objects.objectAt(page, slot);
        objects.clearWeak(object, this);
      }
    }
  }

  /// Closes entry points and finalizers before releasing object storage.
  void close() {
    if (_phase == .closed) return;
    if (_phase != .running) objects.corruptHeap();
    roots.close();
    _phase = .closed;
    try {
      finalization.finishShutdown();
    } finally {
      var page = _pages;
      _pages = null;
      while (page != null) {
        final next = page._next;
        objects.releasePage(page);
        page._next = null;
        page._owner = null;
        page = next;
      }
    }
  }
}
