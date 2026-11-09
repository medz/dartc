@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/integer_operations.dart' as sdk;
import 'fixtures/integer_operations_ffi.dart';

void main() {
  late IntegerOperations native;
  setUpAll(() {
    native = IntegerOperations();
    addTearDown(native.close);
  });

  const values = [
    -0x8000000000000000,
    0x7fffffffffffffff,
    -0x100000001,
    0x100000001,
    -37,
    -1,
    0,
    1,
    2,
    0xaaaaaaaaaaaaaaaa,
    0x5555555555555555,
  ];
  test('native integer operations retain all 64 bits and wrap overflow', () {
    final operations = <(String, BinaryDart, BinaryDart)>[
      ('multiply', native.multiply, sdk.multiply),
      ('and', native.bitAnd, sdk.bitAnd),
      ('or', native.bitOr, sdk.bitOr),
      ('xor', native.bitXor, sdk.bitXor),
      ('overlap', native.overlap, sdk.overlap),
      ('compound', native.compound, sdk.compound),
    ];
    for (final left in values) {
      expect(native.complement(left), sdk.complement(left), reason: '~$left');
      expect(native.same(left), sdk.same(left), reason: 'same $left');
      for (final right in values) {
        for (final (name, actual, expected) in operations) {
          expect(
            actual(left, right),
            expected(left, right),
            reason: '$name $left $right',
          );
        }
      }
    }
  });

  test('integer results survive calls, branches and loop iterations', () {
    for (final seed in values) {
      for (final count in [-3, 0, 1, 2, 7]) {
        expect(
          native.accumulate(seed, count),
          sdk.accumulate(seed, count),
          reason: '$seed $count',
        );
      }
    }
  });
}
