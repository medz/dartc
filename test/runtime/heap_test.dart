import 'dart:io';

import 'package:dartc/sdk.dart';
import 'package:dartc/src/runtime/space.dart';
import 'package:test/test.dart';

void main() {
  test('space reservation leaves state intact when capacity is exhausted', () {
    final space = Space()
      ..start = 4096
      ..capacity = 64;
    expect(space.reserve(24), 4096);
    expect(space.reserve(-8), 0);
    expect(space.reserve(48), 0);
    expect(space.used, 24);
    expect(space.reserve(40), 4120);
    expect(space.contains(4096), isTrue);
    expect(space.contains(4160), isFalse);
    space.scanned = 64;
    space.reset();
    expect(space.used, 0);
    expect(space.scanned, 0);
    expect(space.reserve(64), 4096);
  });

  test('grows semispaces without overflowing the maximum capacity', () {
    const maximum = 0x2000000000000000;
    for (final current in [
      0,
      65536,
      131072,
      maximum ~/ 2,
      maximum - 1,
      maximum,
    ]) {
      for (final needed in [
        0,
        1,
        65536,
        65537,
        maximum - 1,
        maximum,
        maximum + 1,
      ]) {
        final actual = heapCapacity(current, needed);
        if (needed > maximum) {
          expect(actual, 0);
          continue;
        }
        expect(actual, inInclusiveRange(needed, maximum));
        expect(actual, greaterThanOrEqualTo(current));
        if (current <= 131072) {
          final minimum = current == 0 ? 65536 : current;
          final expected = needed <= minimum
              ? BigInt.from(minimum)
              : BigInt.one << (needed - 1).bitLength;
          expect(BigInt.from(actual), expected);
        }
      }
    }
    expect(heapCapacity(-1, 0), 0);
    expect(heapCapacity(0, -1), 0);
    expect(heapCapacity(maximum + 1, 0), 0);
  });

  test('bundles runtime and shared memory contracts unchanged', () async {
    final sources = (await DartSdk.load()).sources;
    for (final path in [
      'src/runtime/heap.dart',
      'src/runtime/space.dart',
      'src/runtime/memory.dart',
      'src/runtime/roots.dart',
      'src/runtime/object_memory.dart',
      'src/layout/memory_layout.dart',
      'layout/memory.dart',
    ]) {
      expect(sources.read('dartc/$path'), File('lib/$path').readAsBytesSync());
    }
  });
}
