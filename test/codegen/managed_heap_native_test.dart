@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/managed_heap_ffi.dart';

void main() {
  test('imported native adapter parks roots across allocating callbacks', () {
    final heap = ManagedHeap();
    addTearDown(heap.close);
    final process = DynamicLibrary.process();
    final malloc = process
        .lookupFunction<
          Pointer<Void> Function(Size),
          Pointer<Void> Function(int)
        >('malloc');
    final free = process
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final storage = malloc(16);
    if (storage.address == 0) throw StateError('malloc failed');
    addTearDown(() => free(storage));
    final values = storage.cast<Int64>();
    var calls = 0;
    var shared = heap.mutateShared(0);
    final comparator = NativeCallable<HeapComparator>.isolateLocal((
      Pointer<Void> left,
      Pointer<Void> right,
    ) {
      calls++;
      expect(heap.chain(40000), 40000 * 39999 ~/ 2);
      shared += 7;
      expect(heap.mutateShared(7), shared);
      expect(heap.chain(40000), 40000 * 39999 ~/ 2);
      return left.cast<Int64>().value < right.cast<Int64>().value ? -1 : 1;
    }, exceptionalReturn: 0);
    addTearDown(comparator.close);
    for (var i = 0; i < 3; i++) {
      values[0] = 20;
      values[1] = 10;
      final before = calls;
      expect(
        heap.importedReenter(storage, comparator.nativeFunction),
        42 + 2 * shared,
      );
      expect(calls, greaterThan(before));
      expect([values[0], values[1]], [10, 20]);
      expect(heap.mutateShared(0), shared);
    }
  });

  test(
    'persistent references and suspended locals survive allocating reentry',
    () {
      final heap = ManagedHeap();
      addTearDown(heap.close);
      heap.writeState(11);
      final initial = heap.mutateShared(0);
      final callback = NativeCallable<HeapCallback>.isolateLocal((int count) {
        expect(heap.chain(count), count * (count - 1) ~/ 2);
        heap.writeState(heap.readState() + 31);
        heap.mutateShared(7);
        expect(heap.chain(count), count * (count - 1) ~/ 2);
      });
      addTearDown(callback.close);
      expect(
        heap.globalReenter(callback.nativeFunction, 40000),
        84 + 2 * (initial + 7),
      );
      expect(heap.readState(), 42);
      expect(
        heap.globalReenter(callback.nativeFunction, 40000),
        115 + 2 * (initial + 14),
      );
      expect(heap.readState(), 73);
    },
  );

  test('native reentry preserves suspended local roots', () {
    final heap = ManagedHeap();
    addTearDown(heap.close);
    var calls = 0;
    final callback = NativeCallable<HeapCallback>.isolateLocal((int count) {
      calls++;
      expect(heap.chain(count), count * (count - 1) ~/ 2);
    });
    addTearDown(callback.close);
    expect(heap.reenter(callback.nativeFunction, 40000), 42);
    expect(calls, 1);
  });

  test('nested native reentry restores every suspended local root', () {
    final heap = ManagedHeap();
    addTearDown(heap.close);
    var depth = 0;
    final results = <int>[];
    late final NativeCallable<HeapCallback> callback;
    callback = NativeCallable<HeapCallback>.isolateLocal((int count) {
      depth++;
      if (depth < 3) {
        results.add(heap.reenter(callback.nativeFunction, count));
      }
      results.add(heap.chain(count));
      depth--;
    });
    addTearDown(callback.close);
    const count = 40000, sum = count * (count - 1) ~/ 2;
    for (var i = 0; i < 2; i++) {
      results.clear();
      expect(heap.reenter(callback.nativeFunction, count), 42);
      expect(results, [sum, 42, sum, 42, sum]);
      expect(depth, 0);
    }
  });

  test('nested callbacks relocate outer aliases and share graph mutations', () {
    final heap = ManagedHeap();
    addTearDown(heap.close);
    heap.writeState(0);
    var shared = heap.mutateShared(0);
    var depth = 0;
    var calls = 0;
    late final NativeCallable<HeapCallback> callback;
    callback = NativeCallable<HeapCallback>.isolateLocal((int count) {
      depth++;
      calls++;
      expect(heap.chain(count), count * (count - 1) ~/ 2);
      shared += 3;
      expect(heap.mutateShared(3), shared);
      if (depth < 3) {
        expect(
          heap.globalReenter(callback.nativeFunction, count),
          42 + 2 * shared,
        );
      }
      expect(heap.chain(count), count * (count - 1) ~/ 2);
      depth--;
    });
    addTearDown(callback.close);
    for (var i = 0; i < 3; i++) {
      expect(
        heap.globalReenter(callback.nativeFunction, 40000),
        42 + 2 * shared,
      );
      expect(heap.mutateShared(0), shared);
      expect(depth, 0);
      expect(calls, 3 * (i + 1));
    }
  });

  test('growing retained chains survive repeated copying collections', () {
    final heap = ManagedHeap();
    addTearDown(heap.close);
    for (final count in [0, 1, 2730, 2731, 10000, 40000]) {
      expect(heap.chain(count), count * (count - 1) ~/ 2);
    }
  });

  test('dead cycles are reclaimed and live aliases retain identity', () {
    final heap = ManagedHeap();
    addTearDown(heap.close);
    for (var i = 0; i < 5; i++) {
      expect(heap.cycles(40000), 123);
    }
  });

  test(
    'constructor receivers and stack arguments survive nested allocation',
    () {
      final heap = ManagedHeap();
      addTearDown(heap.close);
      for (final count in [0, 2731, 40000]) {
        expect(
          heap.nested(-129, -128, -1, 0, 1, 127, 128, 255, 256, count),
          42 + count * (count - 1) ~/ 2,
        );
      }
    },
  );
}
