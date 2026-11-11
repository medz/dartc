@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/numeric_methods.dart' as sdk;
import 'fixtures/numeric_methods_ffi.dart';

void sameDouble(double actual, double expected) {
  if (expected.isNaN) {
    expect(actual.isNaN, isTrue);
  } else {
    int bits(double value) => (ByteData(8)..setFloat64(0, value)).getUint64(0);
    expect(bits(actual), bits(expected), reason: '$actual != $expected');
  }
}

void main() {
  const numbers = [
    double.negativeInfinity,
    -9223372036854775808.0,
    -9007199254740992.0,
    -1.25,
    -double.minPositive,
    -0.0,
    0.0,
    double.minPositive,
    1.25,
    9007199254740992.0,
    9223372036854775808.0,
    double.infinity,
    double.nan,
  ];
  const integers = [
    -0x8000000000000000,
    -9007199254740993,
    -1,
    0,
    1,
    9007199254740993,
    0x7fffffffffffffff,
  ];
  test(
    'SDK numeric methods preserve boxed representations and IEEE values',
    () {
      final native = NumericMethods();
      addTearDown(native.close);
      for (var mode = 0; mode < 8; mode++) {
        for (final value in numbers) {
          sameDouble(native.floating(value, mode), sdk.floating(value, mode));
        }
        for (final value in integers) {
          sameDouble(native.integer(value, mode), sdk.integer(value, mode));
        }
      }
    },
  );
  test('compareTo keeps integer precision through direct, virtual and tear-off calls', () {
    final native = NumericMethods();
    addTearDown(native.close);
    for (final left in numbers) {
      for (final right in numbers) {
        expect(native.order(left, right, 0, 0), sdk.order(left, right, 0, 0));
      }
      for (final integer in integers) {
        for (var mode = 1; mode < 6; mode++) {
          expect(
            native.order(left, 0, integer, mode),
            sdk.order(left, 0, integer, mode),
            reason: '$left / $integer / $mode',
          );
        }
      }
    }
  });
  test('clamp retains bound types, signed zero, NaN and range validation', () {
    final native = NumericMethods();
    addTearDown(native.close);
    for (final value in numbers) {
      for (final lower in numbers) {
        for (final upper in numbers) {
          for (var mode = 0; mode < 3; mode++) {
            sameDouble(
              native.clamp(value, lower, upper, mode),
              sdk.clamp(value, lower, upper, mode),
            );
          }
        }
      }
    }
  });
  test('boxed num arithmetic narrows both operands without losing integer operations', () {
    final native = NumericMethods();
    addTearDown(native.close);
    for (final integer in integers) {
      for (final floating in numbers) {
        for (var shape = 0; shape < 4; shape++) {
          for (var op = 0; op < 4; op++) {
            sameDouble(
              native.arithmetic(integer, floating, shape, op),
              sdk.arithmetic(integer, floating, shape, op),
            );
          }
        }
      }
    }
  });
}
