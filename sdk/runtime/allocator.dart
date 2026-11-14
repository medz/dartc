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
          Pointer<Int64>.fromAddress(context + RuntimeContext.initializing)
                  .value =
              1;
          try {
            page = Page(objects, address, size, capacity);
          } catch (_) {
            Memory.unmap(address, size * capacity);
            rethrow;
          } finally {
            Pointer<Int64>.fromAddress(context + RuntimeContext.initializing)
                    .value =
                0;
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
  final prefix = Pointer<Int64>.fromAddress(descriptor).value;
  var address = 0;
  if (payloadBytes >= 0 && payloadBytes <= 0x0ffffffffffffff8 - prefix) {
    final bytes = (prefix + payloadBytes + 7) & -8;
    address =
        Pointer<Int64>.fromAddress(context + RuntimeContext.initializing)
                .value !=
            0
        ? allocateControl(context, descriptor, bytes)
        : _allocator(context).allocate(context, descriptor, bytes, sp, pc);
  }
  if (address == 0) {
    // Reporting exhaustion must not allocate another exception or stack trace.
    Error.throwWithStackTrace(const OutOfMemoryError(), StackTrace.empty);
  }
  return address;
}

/// Classifies the preallocated failure before the native boundary frees its heap.
@RuntimeEntry(.isOutOfMemory)
@NonAllocating()
bool isOutOfMemory(Object error) => identical(error, const OutOfMemoryError());

Allocator _allocator(int context) {
  var allocator = Memory.objectAt<Allocator?>(
    Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value,
  );
  if (allocator == null) {
    Pointer<Int64>.fromAddress(context + RuntimeContext.initializing).value = 1;
    try {
      final objects = NativeObjects();
      final finalization = FinalizationQueue();
      final events = EventLoop(finalization);
      allocator = Allocator(
        objects,
        NativeRoots(context, objects, events),
        finalization,
        events,
      );
      Pointer<Int64>.fromAddress(context + RuntimeContext.heap)
          .value = Memory.addressOf(
        allocator,
      );
    } catch (_) {
      releaseControl(context);
      rethrow;
    } finally {
      Pointer<Int64>.fromAddress(context + RuntimeContext.initializing).value =
          0;
    }
  }
  return allocator;
}

/// Selects event delivery only for programs that use scheduling facilities.
@RuntimeEntry(.events)
EventLoop events() => _allocator(Memory.context()).events;

/// Runs pending work while the entry frame and heap are still available.
@RuntimeEntry(.runEvents)
void runEvents(int context, bool waitForCallbacks) {
  final allocator = Memory.objectAt<Allocator?>(
    Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value,
  );
  if (allocator != null) {
    allocator.events.run(waitForCallbacks: waitForCallbacks);
  }
}

/// Releases the user heap before destroying its control storage.
@RuntimeEntry(.release)
void release(int context) {
  final allocator = Memory.objectAt<Allocator?>(
    Pointer<Int64>.fromAddress(context + RuntimeContext.heap).value,
  );
  try {
    callbacks.release();
    if (allocator != null) allocator.heap.close();
  } finally {
    releaseControl(context);
  }
}
