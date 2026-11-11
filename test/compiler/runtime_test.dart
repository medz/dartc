@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:dartc/src/runtime/heap.dart' as sdk;
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('source and native memory loops preserve bounds and word bits', () {
    final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
    addTearDown(library.close);
    final copy = library
        .lookupFunction<
          Void Function(Pointer<Int64>, Pointer<Int64>, Int64),
          void Function(Pointer<Int64>, Pointer<Int64>, int)
        >('copy');
    final indirect = library
        .lookupFunction<
          Void Function(Pointer<Int64>, Pointer<Int64>, Int64),
          void Function(Pointer<Int64>, Pointer<Int64>, int)
        >('copyThroughValue');
    final clear = library
        .lookupFunction<
          Void Function(Pointer<Int64>, Int64),
          void Function(Pointer<Int64>, int)
        >('clear');
    final system = DynamicLibrary.process();
    final allocate = system
        .lookupFunction<
          Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)
        >('malloc');
    final free = system
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    const length = 8194, guard = 0x123456789abcdef;
    final memory = allocate(length * 16);
    if (memory.address == 0) throw StateError('Test allocation failed.');
    addTearDown(() => free(memory));
    final source = memory.cast<Int64>();
    final destination = source + length;
    final input = source.asTypedList(length);
    final output = destination.asTypedList(length);
    final original = List.generate(length, (i) => ~(i * 0x9e3779b9));
    input.setAll(0, original);
    for (final (copy, clear) in [
      (sdk.copyWords, sdk.clearWords),
      (copy, clear),
      (indirect, clear),
    ]) {
      copy(nullptr, nullptr, 0);
      clear(nullptr, 0);
      for (final words in [0, 1, 7, 129, length - 2]) {
        output.fillRange(0, length, guard);
        copy(destination + 1, source + 1, words);
        expect(output.sublist(1, words + 1), original.sublist(1, words + 1));
        expect(output.first, guard);
        expect(output.sublist(words + 1), everyElement(guard));
        clear(destination + 1, words);
        expect(output.sublist(1, words + 1), everyElement(0));
        expect(output.first, guard);
        expect(output.sublist(words + 1), everyElement(guard));
        expect(input, original);
      }
    }
  });

  test(
    'compiled heap sizing retains exact large capacities and failure bounds',
    () {
      final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
      addTearDown(library.close);
      final capacity = library
          .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
            'capacity',
          );
      const maximum = 0x2000000000000000;
      for (final (current, needed, expected) in [
        (0, 0, 65536),
        (0, 65537, 131072),
        (131072, 65536, 131072),
        (65536, maximum - 1, maximum),
        (maximum - 1, maximum, maximum),
        (maximum, maximum, maximum),
        (maximum, maximum + 1, 0),
        (-1, 0, 0),
        (0, -1, 0),
        (maximum + 1, 0, 0),
      ]) {
        expect(capacity(current, needed), expected);
      }
    },
  );
}
