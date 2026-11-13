import 'dart:typed_data';

import '../../lib/runtime/contracts.dart';
import 'memory.dart';

_Callbacks? _callbacks;

/// Holds the callback independently of its NativeCallable handle until close.
int register(int entry, Function callback) =>
    (_callbacks ??= _Callbacks()).register(entry, callback);

/// Retrieves a live closure after the native entry has checked its OS thread.
Function target(int address) => _callbacks!._entries[address]!.callback;

/// Releases a registration; an active invocation keeps its own rooted closure.
void unregister(int address) => _callbacks!.unregister(address);

/// Releases all entry mappings before the owning heap is destroyed.
void release() => _callbacks?.close();

final class _Registration(
  final Function callback,
  final _Page page,
  final int slot,
);

final class _Callbacks() {
  final _pages = <_Page>[];
  final _entries = <int, _Registration>{};

  int register(int entry, Function callback) {
    final thread = Memory.currentThread();
    if (thread <= 0) throw StateError('Cannot identify the callback thread.');
    var page = _pages.where((page) => page.available).firstOrNull;
    if (page == null) {
      page = _Page();
      try {
        _pages.add(page);
      } catch (_) {
        page.close();
        rethrow;
      }
    }
    final slot = page.take();
    final address = page.address + slot * NativeCallbackLayout.slotBytes;
    try {
      _entries[address] = _Registration(callback, page, slot);
      Memory.write(address + NativeCallbackLayout.entry, entry);
      Memory.write(address + NativeCallbackLayout.thread, thread);
      return address;
    } catch (_) {
      _entries.remove(address);
      page.give(slot);
      rethrow;
    }
  }

  void unregister(int address) {
    final registration = _entries.remove(address)!;
    registration.page.give(registration.slot);
  }

  void close() {
    for (final page in _pages) {
      page.close();
    }
  }
}

final class _Page() {
  final _free = Uint16List(NativeCallbackLayout.slotCount);
  int _next = 0, _freeCount = 0;
  final int address;

  this : address = Memory.map(2 * NativeCallbackLayout.pageBytes) {
    if (address == 0) throw const OutOfMemoryError();
    try {
      if (!Memory.copyExecutable(
        address,
        Memory.callbackTemplate(),
        NativeCallbackLayout.pageBytes,
      )) {
        throw const OutOfMemoryError();
      }
    } catch (_) {
      close();
      rethrow;
    }
  }

  bool get available =>
      _freeCount != 0 || _next < NativeCallbackLayout.slotCount;
  int take() => _freeCount == 0 ? _next++ : _free[--_freeCount];
  void give(int slot) => _free[_freeCount++] = slot;
  void close() => Memory.unmap(address, 2 * NativeCallbackLayout.pageBytes);
}
