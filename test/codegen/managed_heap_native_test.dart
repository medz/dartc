@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:test/test.dart';

import 'fixtures/managed_heap_ffi.dart';

void main() {
  test(
    'persistent scalar state is shared across allocating native reentry',
    () {
      final heap = ManagedHeap();
      addTearDown(heap.close);
      heap.writeState(11);
      final callback = NativeCallable<HeapCallback>.isolateLocal((int count) {
        expect(heap.chain(count), count * (count - 1) ~/ 2);
        heap.writeState(heap.readState() + 31);
      });
      addTearDown(callback.close);
      expect(heap.globalReenter(callback.nativeFunction, 40000), 84);
      expect(heap.readState(), 42);
      expect(heap.globalReenter(callback.nativeFunction, 40000), 115);
      expect(heap.readState(), 73);
    },
  );

  test('native reentry preserves the suspended activation heap', () {
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

  test('nested native reentry restores every suspended activation heap', () {
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
