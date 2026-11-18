import 'dart:ffi';

import 'package:dartc/layout/memory.dart';
import 'package:test/test.dart';

import '../../sdk/runtime/control.dart';
import '../../sdk/runtime/roots.dart';
import '../../sdk/runtime/module_roots.dart';
import 'fixtures/heap_model.dart';

final class Storage() {
  final _allocate = DynamicLibrary.process()
      .lookupFunction<
        Pointer<Uint8> Function(Size, Size),
        Pointer<Uint8> Function(int, int)
      >('calloc');
  final _free = DynamicLibrary.process()
      .lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)
      >('free');
  final _regions = <Pointer<Uint8>>[];
  late final int context = allocate(RuntimeContext.size);

  int allocate(int bytes) {
    final region = _allocate(1, bytes);
    if (region == nullptr) throw StateError('Cannot allocate test storage.');
    _regions.add(region);
    return region.address;
  }

  int block(List<int> sizes, {int next = 0, int extra = 0}) {
    final bytes = sizes.fold(0, (sum, size) => sum + size);
    final capacity = ControlBlock.headerBytes + bytes + extra;
    final address = allocate(capacity);
    word(address + ControlBlock.next).value = next;
    word(address + ControlBlock.capacity).value = capacity;
    word(address + ControlBlock.initializedEnd).value =
        address + ControlBlock.headerBytes + bytes;
    var cursor = address + ControlBlock.headerBytes;
    for (final size in sizes) {
      word(cursor + ObjectHeader.descriptorOffset).value = 1;
      word(cursor + ObjectHeader.sizeOffset).value = size;
      cursor += size;
    }
    return address;
  }

  void close() {
    for (final region in _regions) {
      _free(region);
    }
  }
}

Pointer<Int64> word(int address) => Pointer<Int64>.fromAddress(address);

List<int> addresses(ControlObjects objects) {
  objects.start();
  final result = <int>[];
  while (objects.moveNext()) {
    result.add(objects.address);
  }
  expect(objects.address, 0);
  return result;
}

void main() {
  late Storage storage;
  late ControlObjects objects;
  setUp(() {
    storage = Storage();
    objects = ControlObjects(storage.context, HeapModel());
    addTearDown(storage.close);
  });

  test('empty control storage has no objects', () {
    expect(addresses(objects), isEmpty);
  });

  test('module registry enumerates all identities on every scan', () {
    final roots = ModuleRoots(storage.context);
    roots.start();
    expect(roots.moveNext(), isFalse);
    final entries = [
      storage.allocate(40),
      storage.allocate(40),
      storage.allocate(40),
    ];
    final table = storage.allocate(
      ModuleRootTable.entries + entries.length * ModuleRootTable.entrySize,
    );
    word(table + ModuleRootTable.count).value = entries.length;
    for (final (index, address) in entries.indexed) {
      word(table + ModuleRootTable.entries + index * ModuleRootTable.entrySize)
              .value =
          address;
    }
    word(storage.context + RuntimeContext.globalRoots).value = table;
    for (var scan = 0; scan < 3; scan++) {
      roots.start();
      final actual = <int>[];
      while (roots.moveNext()) {
        actual.add(roots.address);
      }
      expect(actual, entries);
      expect(roots.address, 0);
    }
    word(storage.context + RuntimeContext.globalRoots).value = 0;
    roots.start();
    expect(roots.moveNext(), isFalse);
  });

  test('native roots own managed, collecting and closed phase transitions', () {
    final model = HeapModel();
    final roots = NativeRoots(storage.context, model);
    final phase = word(storage.context + RuntimeContext.phase);
    phase.value = RuntimePhase.managed;
    expect(roots.stop, throwsStateError);
    expect(phase.value, RuntimePhase.managed);
    roots.publish(1, 2);
    expect(roots.stop(), isTrue);
    expect(phase.value, RuntimePhase.collecting);
    expect(() => roots.publish(3, 4), throwsStateError);
    expect(roots.stop, throwsStateError);
    expect(roots.close, throwsStateError);
    roots.traceConditional(model.heap, model.heap);
    roots.clearWeak(model.heap);
    roots.resume();
    expect(phase.value, RuntimePhase.managed);
    roots.close();
    expect(phase.value, RuntimePhase.closed);
    roots.close();
    expect(() => roots.publish(3, 4), throwsStateError);
  });

  test('root operations reject invalid phases before changing context', () {
    final model = HeapModel();
    final roots = NativeRoots(storage.context, model);
    final phase = word(storage.context + RuntimeContext.phase);
    for (final invalid in [
      RuntimePhase.dormant,
      RuntimePhase.bootstrap,
      RuntimePhase.control,
      RuntimePhase.closed,
      -1,
      6,
      0x7fffffffffffffff,
    ]) {
      phase.value = invalid;
      expect(() => roots.publish(1, 2), throwsStateError);
      expect(roots.stop, throwsStateError);
      expect(roots.resume, throwsStateError);
      expect(() => roots.visit(model.heap), throwsStateError);
      expect(
        () => roots.traceConditional(model.heap, model.heap),
        throwsStateError,
      );
      expect(() => roots.clearWeak(model.heap), throwsStateError);
      if (invalid != RuntimePhase.closed) {
        expect(roots.close, throwsStateError);
      }
      expect(phase.value, invalid);
    }
  });

  test(
    'publishing invalid stack locations leaves the managed phase intact',
    () {
      final roots = NativeRoots(storage.context, HeapModel());
      final phase = word(storage.context + RuntimeContext.phase);
      phase.value = RuntimePhase.managed;
      expect(() => roots.publish(0, 2), throwsStateError);
      expect(() => roots.publish(1, 0), throwsStateError);
      expect(roots.stop, throwsStateError);
      expect(phase.value, RuntimePhase.managed);
    },
  );

  test('walks initialized objects across chunks and ignores unused tails', () {
    final first = storage.block([40, 48], extra: 64);
    final second = storage.block([56], next: first, extra: 128);
    final empty = storage.block([], next: second);
    word(storage.context + RuntimeContext.bootstrap).value = empty;
    final expected = [
      second + ControlBlock.headerBytes,
      first + ControlBlock.headerBytes,
      first + ControlBlock.headerBytes + 40,
    ];
    expect(addresses(objects), expected);
    expect(addresses(objects), expected);
  });

  test(
    'an object is invisible until its initialized frontier is published',
    () {
      final block = storage.block([40, 48]);
      word(storage.context + RuntimeContext.bootstrap).value = block;
      final first = block + ControlBlock.headerBytes;
      word(block + ControlBlock.initializedEnd).value = first + 40;
      expect(addresses(objects), [first]);
      word(block + ControlBlock.initializedEnd).value = first + 40 + 48;
      expect(addresses(objects), [first, first + 40]);
    },
  );

  test('rejects invalid frontiers before reading an incomplete header', () {
    final block = storage.block([48], extra: 64);
    word(storage.context + RuntimeContext.bootstrap).value = block;
    for (final offset in [0, 16, 25, 32, 144]) {
      word(block + ControlBlock.initializedEnd).value = block + offset;
      expect(() => addresses(objects), throwsStateError, reason: '$offset');
    }
  });

  test('rejects uninitialized, unaligned and overlapping object extents', () {
    final block = storage.block([48], extra: 64);
    word(storage.context + RuntimeContext.bootstrap).value = block;
    final object = block + ControlBlock.headerBytes;
    for (final size in [0, 32, 41, 56]) {
      word(object + ObjectHeader.sizeOffset).value = size;
      expect(() => addresses(objects), throwsStateError, reason: '$size');
    }
    word(object + ObjectHeader.sizeOffset).value = 48;
    word(object + ObjectHeader.descriptorOffset).value = 0;
    expect(() => addresses(objects), throwsStateError);
  });

  test('rejects malformed chunk capacities and resets after release', () {
    final block = storage.block([48]);
    word(storage.context + RuntimeContext.bootstrap).value = block;
    for (final capacity in [0, 16, 25, 64]) {
      word(block + ControlBlock.capacity).value = capacity;
      expect(() => addresses(objects), throwsStateError, reason: '$capacity');
    }
    word(storage.context + RuntimeContext.bootstrap).value = 0;
    expect(addresses(objects), isEmpty);
  });
}
