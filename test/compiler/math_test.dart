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
}
