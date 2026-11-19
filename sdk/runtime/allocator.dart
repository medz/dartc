import 'dart:ffi';

import '../../lib/layout/memory.dart';
import '../../lib/runtime/contracts.dart';
import 'control.dart';
import 'finalization.dart';
import 'event_loop.dart';
import 'heap.dart';
import 'memory.dart';
import 'native_objects.dart';
import 'object_memory.dart';
import 'roots.dart';
import 'native_callbacks.dart' as callbacks;

/// Owns allocation policy while the heap owns reachability and reclamation.
final class Allocator(
  final NativeObjects objects,
  final NativeRoots roots,
  final FinalizationQueue finalization,
  final EventLoop events,
) {
  final Heap heap = Heap(objects, roots, finalization);
  int _identityHash = 0;
  int _allocatedBytes = 0, _collectionBudget = 65536;
  int _externalAtCollection = 0;
  void Function(EventLoop, bool)? _drainEvents;

  void _collect() {
    heap.collect();
    finalization.drainNative();
    _allocatedBytes = 0;
    _externalAtCollection = finalization.externalBytes;
    final live = heap.liveBytes > 0x7fffffffffffffff - _externalAtCollection
        ? 0x7fffffffffffffff
        : heap.liveBytes + _externalAtCollection;
    _collectionBudget = live > 65536 ? live : 65536;
  }

  int allocate(int context, int descriptor, int bytes, int sp, int pc) {
    roots.publish(sp, pc);
    final size = slotSize(bytes);
    if (size == 0) return 0;
    var page = heap.availablePage(size);
    var collected = false;
    final externalGrowth = finalization.externalBytes > _externalAtCollection
        ? finalization.externalBytes - _externalAtCollection
        : 0;
    if (page == null && _allocatedBytes >= _collectionBudget - externalGrowth) {
      _collect();
      collected = true;
      page = heap.availablePage(size);
    }
    if (page == null) {
      final capacity = size <= 4096 ? 64 : 1;
      var address = Memory.map(size * capacity);
      if (address == 0 && !collected) {
        _collect();
        page = heap.availablePage(size);
        if (page == null) address = Memory.map(size * capacity);
      }
      if (page == null) {
        if (address == 0) return 0;
        page = heap.emptyPage;
        if (page != null) {
          page.replaceStorage(address, size, capacity);
        } else {
          final phase = Pointer<Int64>.fromAddress(
            context + RuntimeContext.phase,
          );
          if (phase.value != RuntimePhase.managed) Memory.fail();
          phase.value = RuntimePhase.control;
          try {
            page = Page(objects, address, size, capacity);
          } catch (_) {
            Memory.unmap(address, size * capacity);
            rethrow;
          } finally {
            if (phase.value != RuntimePhase.control) Memory.fail();
            phase.value = RuntimePhase.managed;
          }
          heap.addPage(page);
        }
      }
    }
    final slot = page.reserve();
    if (slot < 0) Memory.fail();
    final address = page.address + slot * size;
    _identityHash = (_identityHash + 0x9e3779b9) & 0x3fffffff;
    ObjectMemory.initialize(address, descriptor, bytes, _identityHash, page);
    _allocatedBytes += size;
    return address;
  }
}

/// Rounds allocation sizes without overflowing the supported address range.
int slotSize(int bytes) {
  if (bytes <= 0 || bytes > 0x1000000000000000) return 0;
  var size = 64;
  while (size < bytes) {
    size *= 2;
  }
  return size;
}

/// Returns nonzero storage or throws OutOfMemoryError after allocation fails.
@RuntimeEntry(.allocate)
int allocate(int context, int descriptor, int sp, int pc, int payloadBytes) {
  final phase = Pointer<Int64>.fromAddress(context + RuntimeContext.phase)
      .value;
  if (phase != RuntimePhase.dormant &&
      phase != RuntimePhase.bootstrap &&
      phase != RuntimePhase.managed &&
      phase != RuntimePhase.control) {
    Memory.fail();
  }
  final prefix = Pointer<Int64>.fromAddress(descriptor).value;
  var address = 0;
  if (payloadBytes >= 0 && payloadBytes <= 0x0ffffffffffffff8 - prefix) {
    final bytes = (prefix + payloadBytes + 7) & -8;
    address = phase == RuntimePhase.bootstrap || phase == RuntimePhase.control
        ? allocateControl(context, descriptor, bytes)
        : _allocator(context).allocate(context, descriptor, bytes, sp, pc);
  }
  if (address == 0) allocationFailure();
  return address;
}

/// Reports exhaustion without allocating an exception or a stack trace.
@RuntimeEntry(.allocationFailure)
Never allocationFailure() =>
    Error.throwWithStackTrace(const OutOfMemoryError(), StackTrace.empty);

/// Classifies the preallocated failure before the native boundary frees its heap.
@RuntimeEntry(.isOutOfMemory)
@NonAllocating()
bool isOutOfMemory(Object error) => identical(error, const OutOfMemoryError());

Allocator _allocator(int context) {
  final phase = Pointer<Int64>.fromAddress(context + RuntimeContext.phase);
  final address = Pointer<Int64>.fromAddress(context + RuntimeContext.heap)
      .value;
  if (phase.value == RuntimePhase.managed) {
    if (address == 0) Memory.fail();
    return Memory.objectAt<Allocator>(address);
  }
  if (phase.value != RuntimePhase.dormant || address != 0) Memory.fail();
  phase.value = RuntimePhase.bootstrap;
  try {
    final objects = NativeObjects();
    final finalization = FinalizationQueue();
    final events = EventLoop(finalization);
    final allocator = Allocator(
      objects,
      NativeRoots(context, objects),
      finalization,
      events,
    );
    Pointer<Int64>.fromAddress(context + RuntimeContext.heap)
        .value = Memory.addressOf(
      allocator,
    );
    phase.value = RuntimePhase.managed;
    return allocator;
  } catch (_) {
    releaseControl(context);
    rethrow;
  }
}

/// Finalizers share the active heap's queue. Collections and shutdown
/// deliver native records while they still own that heap.
FinalizationQueue finalizers() => _allocator(Memory.context()).finalization;

/// Registers event delivery when scheduling facilities are first used.
EventLoop events() {
  final allocator = _allocator(Memory.context());
  allocator._drainEvents = _drain;
  return allocator.events;
}

void _drain(EventLoop loop, bool waitForCallbacks) =>
    loop.run(waitForCallbacks: waitForCallbacks);

/// Runs pending work while the entry frame and heap are still available.
@RuntimeEntry(.runEvents)
void runEvents(int context, bool waitForCallbacks) {
  final allocator = Memory.objectAt<Allocator?>(
    Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value,
  );
  if (allocator != null) {
    allocator._drainEvents?.call(allocator.events, waitForCallbacks);
  }
}

/// Releases the user heap before destroying its control storage.
@RuntimeEntry(.release)
void release(int context) {
  final allocator = Memory.objectAt<Allocator?>(
    Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value,
  );
  try {
    try {
      callbacks.release();
    } finally {
      if (allocator != null) allocator.heap.close();
    }
  } finally {
    releaseControl(context);
  }
}
