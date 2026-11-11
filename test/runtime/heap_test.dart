import 'dart:io';

import 'package:dartc/sdk.dart';
import 'package:dartc/src/runtime/heap.dart';
import 'package:test/test.dart';

void main() {
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

  test('bundles the maintained runtime source unchanged', () async {
    expect(
      (await DartSdk.load()).sources.read('runtime/heap.dart'),
      File('lib/src/runtime/heap.dart').readAsBytesSync(),
    );
  });
}
