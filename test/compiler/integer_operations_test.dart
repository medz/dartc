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

  test('integer division and both remainders preserve signs and overflow', () {
    for (final left in values) {
      for (final right in values.where((n) => n != 0)) {
        final a = BigInt.from(left), b = BigInt.from(right);
        final quotient = (a ~/ b).toSigned(64).toInt();
        final remainder = a.remainder(b).toInt();
        final modulo = (a % b).toInt();
        expect(
          native.truncate(left, right),
          quotient,
          reason: '$left ~/ $right',
        );
        expect(
          native.remainder(left, right),
          remainder,
          reason: '$left.remainder($right)',
        );
        expect(native.modulo(left, right), modulo, reason: '$left % $right');
        expect(sdk.truncate(left, right), quotient);
        expect(sdk.remainder(left, right), remainder);
        expect(sdk.modulo(left, right), modulo);
        expect(
          native.divideCompound(left, right),
          sdk.divideCompound(left, right),
        );
      }
    }
  });

  test(
    'ignored division results still throw after operands and run finally',
    () {
      expect(sdk.divisionType(), 1);
      expect(native.divisionType(), 1);
      for (final kind in [0, 1, 2]) {
        expect(sdk.divisionFailure(7, kind), 7074);
        expect(native.divisionFailure(7, kind), 7074);
      }
    },
  );
}
