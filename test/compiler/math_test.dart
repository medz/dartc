@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/math.dart' as sdk;
import 'fixtures/math_ffi.dart';

int bits(double value) => (ByteData(8)..setFloat64(0, value)).getInt64(0);

void expectDouble(double actual, double expected) {
  if (expected.isNaN) {
    expect(actual.isNaN, isTrue);
  } else {
    expect(bits(actual), bits(expected));
  }
}

void expectMath(double actual, double expected) {
  if (!expected.isFinite || expected == 0) {
    expectDouble(actual, expected);
  } else {
    expect(actual.isFinite, isTrue);
    expect(actual.isNegative, expected.isNegative);
    expect((bits(actual) - bits(expected)).abs(), lessThanOrEqualTo(4));
  }
}

void main() {
  late MathLibrary library;
  setUpAll(() {
    library = MathLibrary();
    addTearDown(library.close);
  });

  test(
    'square roots preserve exact results, negative zero and special values',
    () {
      for (final (input, expected) in [
        (0.0, 0.0),
        (-0.0, -0.0),
        (1.0, 1.0),
        (4.0, 2.0),
        (81.0, 9.0),
        (double.minPositive, 2.2227587494850775e-162),
        (double.infinity, double.infinity),
        (-double.infinity, double.nan),
        (-1.0, double.nan),
        (double.nan, double.nan),
      ]) {
        expectDouble(library.squareRoot(input), expected);
      }
      for (final input in [2.0, 1e-310, 1e-200, 1e200, double.maxFinite]) {
        expectDouble(library.squareRoot(input), math.sqrt(input));
      }
    },
  );

  test('integer inputs round to double before taking the square root', () {
    for (final input in [
      -0x8000000000000000,
      -1,
      0,
      1,
      4,
      9007199254740991,
      9007199254740993,
      0x7fffffffffffffff,
    ]) {
      expectDouble(library.integerRoot(input), math.sqrt(input.toDouble()));
    }
  });

  test('operands survive calls and loops and are evaluated exactly once', () {
    for (final input in [-0.0, 2.0, 81.0, double.infinity, double.nan]) {
      expectDouble(library.liveInput(input), sdk.liveInput(input));
      expectDouble(library.nested(input), sdk.nested(input));
      for (final count in [0, 1, 37]) {
        expectDouble(library.iterate(count, input), sdk.iterate(count, input));
      }
    }
    library.memory.value = 9;
    expect(library.ordered(library.memory), 3);
    expect(library.memory.value, 10);
    expect(library.shadowed(9), 128);
  });

  test(
    'num arguments and function values retain conversion and special values',
    () {
      for (final (floating, integer) in [
        (-0.0, -1),
        (0.0, 0),
        (2.0, 4),
        (double.minPositive, 9007199254740993),
        (double.maxFinite, 0x7fffffffffffffff),
        (double.infinity, -0x8000000000000000),
        (double.nan, 81),
      ]) {
        for (var mode = 0; mode < 8; mode++) {
          expectDouble(
            library.boxedRoot(floating, integer, mode),
            math.sqrt(mode.isEven ? floating : integer),
          );
        }
      }
    },
  );

  test('direct and dynamic function calls reject non-numeric arguments', () {
    for (var mode = 0; mode < 6; mode++) {
      expect(library.rejectedRoot(mode), 1, reason: 'argument/call $mode');
    }
  });

  test('floating math preserves exact special values and signed zero', () {
    for (final (operation, x, y, expected) in [
      (0, -0.0, 0.0, -0.0),
      (0, double.minPositive, 0.0, double.minPositive),
      (0, double.infinity, 0.0, double.nan),
      (1, 0.0, 0.0, 1.0),
      (2, -0.0, 0.0, -0.0),
      (3, -0.0, 0.0, -0.0),
      (3, 2.0, 0.0, double.nan),
      (4, 1.0, 0.0, 0.0),
      (4, -2.0, 0.0, double.nan),
      (5, -0.0, 0.0, -0.0),
      (6, 0.0, 0.0, 1.0),
      (6, -double.infinity, 0.0, 0.0),
      (6, double.infinity, 0.0, double.infinity),
      (7, 1.0, 0.0, 0.0),
      (7, 0.0, 0.0, -double.infinity),
      (7, -0.0, 0.0, -double.infinity),
      (7, -1.0, 0.0, double.nan),
      (8, -0.0, 1.0, -0.0),
      (9, double.nan, 0.0, 1.0),
      (9, 1.0, double.nan, 1.0),
      (9, double.nan, 1.0, double.nan),
      (9, -0.0, 3.0, -0.0),
      (9, -0.0, -3.0, -double.infinity),
      (9, -double.infinity, -3.0, -0.0),
      (9, -double.infinity, 3.0, -double.infinity),
      (9, -2.0, 0.5, double.nan),
      (9, -1.0, double.infinity, 1.0),
      (9, 0.5, double.infinity, 0.0),
      (9, 2.0, -double.infinity, 0.0),
    ]) {
      expectDouble(library.floatingMath(operation, x, y), expected);
    }
  });

  test('transcendentals match SDK precision across domains and extremes', () {
    final functions = [
      math.sin,
      math.cos,
      math.tan,
      math.asin,
      math.acos,
      math.atan,
      math.exp,
      math.log,
    ];
    for (var operation = 0; operation < functions.length; operation++) {
      for (final input in [
        -double.infinity,
        -double.maxFinite,
        -1e300,
        -1000.0,
        -math.pi,
        -1.0,
        -0.5,
        -double.minPositive,
        -0.0,
        0.0,
        double.minPositive,
        0.5,
        1.0,
        math.pi / 2,
        math.pi,
        1000.0,
        1e300,
        double.maxFinite,
        double.infinity,
        double.nan,
      ]) {
        expectMath(
          library.floatingMath(operation, input, 0),
          functions[operation](input),
        );
      }
    }
    for (final x in [
      -double.infinity,
      -1.0,
      -0.0,
      0.0,
      1.0,
      double.infinity,
      double.nan,
    ]) {
      for (final y in [
        -double.infinity,
        -1.0,
        -0.0,
        0.0,
        1.0,
        double.infinity,
        double.nan,
      ]) {
        expectMath(library.floatingMath(8, x, y), math.atan2(x, y));
      }
    }
    for (final (x, y) in [
      (0.1, 0.3),
      (1.0001, 1000.0),
      (2.0, -1074.0),
      (2.0, -1075.0),
      (double.maxFinite, 2.0),
      (double.minPositive, 0.5),
      (-2.0, 51.0),
      (-2.0, -51.0),
      (1e-200, -2.0),
    ]) {
      expectMath(library.floatingMath(9, x, y), math.pow(x, y).toDouble());
    }
  });

  test('integer powers retain the SDK algorithm, result type and overflow', () {
    for (final base in [
      0,
      1,
      -1,
      2,
      -2,
      9,
      0x7fffffffffffffff,
      -0x8000000000000000,
    ]) {
      for (final exponent in [
        0,
        1,
        2,
        3,
        31,
        32,
        63,
        64,
        127,
        0x7fffffffffffffff,
      ]) {
        expect(library.integerPower(base, exponent), math.pow(base, exponent));
      }
    }
    expect(library.integerPower(0, 0), 1);
    expect(library.integerPower(2, 63), -0x8000000000000000);
  });

  test('function values retain num conversion, types and dynamic checks', () {
    for (final (floating, integer) in [
      (-0.0, -1),
      (0.5, 2),
      (double.minPositive, 9007199254740993),
      (double.infinity, 0x7fffffffffffffff),
      (double.nan, 0),
    ]) {
      for (var mode = 0; mode < 12; mode++) {
        final num value = mode.isEven ? floating : integer;
        final expected = mode < 4
            ? math.sin(value)
            : math.pow(value, mode < 8 ? 3 : -3).toDouble();
        expectMath(library.indirectMath(floating, integer, mode), expected);
      }
    }
    for (var mode = 0; mode < 9; mode++) {
      expect(library.rejectedMath(mode), 1);
    }
  });

  test('system calls retain live operands and source evaluation order', () {
    for (final (x, y) in [(0.5, 1.5), (2.0, 3.0), (-2.0, 0.5), (3.0, -7.0)]) {
      expectMath(library.composed(x, y), sdk.composed(x, y));
    }
    library.memory.value = 2;
    expect(library.orderedPower(library.memory), 8);
    expect(library.memory.value, 4);
  });
}
