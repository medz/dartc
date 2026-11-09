import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../support/numeric_order.dart';
import 'fixtures/mixed_numeric.dart' as sdk;
import 'fixtures/mixed_numeric_ffi.dart';

int bits(double value) => (ByteData(8)..setFloat64(0, value)).getInt64(0);
double fromBits(int value) => (ByteData(8)..setInt64(0, value)).getFloat64(0);

void expectDouble(double actual, double expected) {
  if (expected.isNaN) {
    expect(actual.isNaN, isTrue);
  } else {
    expect(bits(actual), bits(expected));
  }
}

int mask(int? order) => switch (order) {
  null => 2,
  < 0 => 14,
  0 => 41,
  _ => 50,
};

void main() {
  final library = NumericLibrary();
  tearDownAll(library.close);
  const integers = [
    -0x8000000000000000,
    -0x7fffffffffffffff,
    -9007199254740995,
    -9007199254740993,
    -9007199254740992,
    -9007199254740991,
    -3,
    -1,
    0,
    1,
    3,
    9007199254740991,
    9007199254740992,
    9007199254740993,
    9007199254740995,
    0x7ffffffffffffbff,
    0x7ffffffffffffffe,
    0x7fffffffffffffff,
  ];
  const doubles = [
    -double.infinity,
    -1e300,
    -9223372036854775808.0,
    -9007199254740994.0,
    -9007199254740992.0,
    -3.5,
    -1.0,
    -1e-310,
    -0.0,
    0.0,
    1e-310,
    1.0,
    3.5,
    9007199254740992.0,
    9007199254740994.0,
    9223372036854774784.0,
    9223372036854775808.0,
    1e300,
    double.infinity,
    double.nan,
  ];

  void compare(int i, double d) {
    final order = numericOrder(i, d);
    expect(library.comparisons(i, d), mask(order), reason: '$i versus $d');
    expect(
      library.reverseComparisons(d, i),
      mask(order == null ? null : -order),
      reason: '$d versus $i',
    );
  }

  test('mixed comparisons preserve exact values instead of SDK rounding', () {
    expect(numericOrder(9007199254740993, 9007199254740992.0), 1);
    expect(numericOrder(0x7fffffffffffffff, 9223372036854775808.0), -1);
    expect(library.constantComparison(), 0);
    expect(library.constantValues(), 14);
    expect(library.namedConstants(), 370);
    for (final i in integers) {
      for (final d in doubles) {
        compare(i, d);
      }
    }
    for (var exponent = 0; exponent < 63; exponent++) {
      for (final delta in [-3, -1, 0, 1, 3]) {
        final value = (1 << exponent) + delta;
        for (final i in [value, -value]) {
          final rounded = bits(i.toDouble());
          for (final offset in [-1, 0, 1]) {
            compare(i, fromBits(rounded + offset));
          }
        }
      }
    }
    final random = Random(0x15);
    int word() => random.nextInt(1 << 32) << 32 | random.nextInt(1 << 32);
    for (var i = 0; i < 1024; i++) {
      compare(word(), fromBits(word()));
    }
  });

  test('mixed arithmetic and conversions preserve IEEE results', () {
    final reference = [sdk.add, sdk.subtract, sdk.multiply, sdk.divide];
    final reverse = [
      sdk.reverseAdd,
      sdk.reverseSubtract,
      sdk.reverseMultiply,
      sdk.reverseDivide,
    ];
    for (final i in integers) {
      expectDouble(library.converted(i), sdk.converted(i));
      for (final other in integers) {
        expectDouble(library.divideInts(i, other), sdk.divideInts(i, other));
      }
      for (final d in doubles) {
        for (var operation = 0; operation < reference.length; operation++) {
          expectDouble(
            library.binary[operation](i, d),
            reference[operation](i, d),
          );
          expectDouble(
            library.reverseBinary[operation](d, i),
            reverse[operation](d, i),
          );
        }
      }
    }
    for (final d in [...doubles, fromBits(0x7ff8123456789abc)]) {
      expect(bits(library.doubleIdentity(d)), bits(sdk.doubleIdentity(d)));
    }
  });

  test('conversion temporaries survive pressure, calls and loop transfers', () {
    for (final d in doubles) {
      for (final i in integers) {
        expectDouble(library.pressure(i, d), sdk.pressure(i, d));
      }
      for (final count in [0, 1, 19]) {
        expectDouble(library.loop(count, d), sdk.loop(count, d));
      }
    }
  });

  test(
    'mixed comparisons retain operand evaluation and native write order',
    () {
      for (final i in integers) {
        for (final delta in [-0.5, 0.0, 0.5, 1.0, double.nan]) {
          library.memory.value = i;
          final order = numericOrder(i, (i + 1) + delta);
          expect(
            library.orderedComparison(library.memory, delta),
            order != null && order < 0 ? 1 : 0,
          );
          expect(library.memory.value, i + 2);
        }
      }
    },
  );
}
