import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/doubles.dart' as sdk;
import 'fixtures/doubles_ffi.dart';

int bits(double value) => (ByteData(8)..setFloat64(0, value)).getInt64(0);

void sameDouble(double actual, double expected) {
  if (expected.isNaN) {
    expect(actual.isNaN, isTrue);
  } else {
    expect(bits(actual), bits(expected));
  }
}

void main() {
  final library = DoubleLibrary();
  tearDownAll(library.close);
  final values = [
    0.0,
    -0.0,
    1.0,
    -1.5,
    1e-310,
    -1e-310,
    1e200,
    -1e200,
    double.infinity,
    double.negativeInfinity,
    double.nan,
    (ByteData(8)..setInt64(0, 0x7ff8123456789abc)).getFloat64(0),
  ];

  test('double operations preserve IEEE values and unordered comparisons', () {
    final reference = [sdk.add, sdk.subtract, sdk.multiply, sdk.divide];
    for (final left in values) {
      expect(bits(library.negate(left)), bits(sdk.negate(left)));
      for (final right in values) {
        for (var i = 0; i < reference.length; i++) {
          sameDouble(library.binary[i](left, right), reference[i](left, right));
        }
        expect(library.comparisons(left, right), sdk.comparisons(left, right));
      }
    }
  });

  test('double constants and register pressure preserve bits', () {
    final reference = [sdk.negativeZero, sdk.tiny, sdk.infinity, sdk.nan];
    for (var i = 0; i < reference.length; i++) {
      sameDouble(library.constants[i](), reference[i]());
    }
    for (final value in values) {
      sameDouble(library.pressure(value), sdk.pressure(value));
    }
  });

  test('floating loop arguments and calls retain simultaneous transfers', () {
    for (final count in [-1, 0, 1, 2, 19]) {
      for (final left in values) {
        sameDouble(
          library.rotate(left, -2.5, count),
          sdk.rotate(left, -2.5, count),
        );
      }
    }
  });

  test(
    'mixed banks, stack arguments and constant temporaries remain separate',
    () {
      for (final (native, reference) in [
        (library.mixed, sdk.mixed),
        (library.forward, sdk.forward),
      ]) {
        for (final sign in [1, -1]) {
          final actual = native(
            library.memory,
            1.25,
            sign,
            2.5,
            2,
            3.75,
            3,
            4.5,
            4,
            5.25,
            5,
            6.5,
            6,
            7.75,
            7,
            8.5,
            8,
            9.25,
            9,
          );
          final storage = library.memory.value;
          sameDouble(
            actual,
            reference(
              library.memory,
              1.25,
              sign,
              2.5,
              2,
              3.75,
              3,
              4.5,
              4,
              5.25,
              5,
              6.5,
              6,
              7.75,
              7,
              8.5,
              8,
              9.25,
              9,
            ),
          );
          expect(library.memory.value, storage);
        }
      }
      final actual = library.constantsInCall(library.memory);
      final storage = library.memory.value;
      sameDouble(actual, sdk.constantsInCall(library.memory));
      expect(library.memory.value, storage);
    },
  );
}
