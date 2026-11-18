@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/scalar_representation_ffi.dart';

void main() {
  late ScalarRepresentation native;
  setUpAll(() {
    native = ScalarRepresentation();
    addTearDown(native.close);
  });

  test(
    'bounded generic fields survive independent entries and recursive calls',
    () {
      for (final (integer, floating, flag) in [
        (0x123456789abc, -73.25, 1),
        (-0x123456789abc, -0.0, 0),
        (0, double.infinity, 1),
      ]) {
        native.storeScalars(integer, floating, flag);
        for (final depth in [0, 1, 17]) {
          expect(native.readInteger(depth), integer);
          expect(_bits(native.readFloating(depth)), _bits(floating));
          expect(native.readFlag(depth), flag);
        }
        native.replaceScalars(-integer, 19.75, 1 - flag);
        expect(native.readInteger(13), -integer);
        expect(native.readFloating(13), 19.75);
        expect(native.readFlag(13), 1 - flag);
      }
    },
  );

  test(
    'escaping generic captures preserve mutable cells and immutable values',
    () {
      final nan = _double(0x7ff8000000000042);
      native.storeCaptures(-41, 0x123456789abc, -0.0, nan, 0, 1);
      expect(native.capturedInteger(0), -41);
      expect(_bits(native.capturedFloating(0)), _bits(-0.0));
      expect(native.capturedFlag(0), 0);
      expect(native.capturedInteger(1), 0x123456789abc);
      expect(_bits(native.capturedFloating(1)), _bits(nan));
      expect(native.capturedFlag(1), 1);
      expect(native.capturedInteger(0), 0x123456789abc);
      expect(_bits(native.capturedFloating(0)), _bits(nan));
      expect(native.capturedFlag(0), 1);
    },
  );

  test('late generic scalars keep state, finality and covariant checks', () {
    native.storeScalars(0, 0.0, 0);
    expect(native.lateErrors(), 1);
    // The preceding check initialized the final flag; use a fresh owner.
    native.storeScalars(0, 0.0, 0);
    native.storeLateScalars(-73, -0.0, 1);
    expect(native.readLateInteger(), -73);
    expect(_bits(native.readLateFloating()), _bits(-0.0));
    expect(native.readLateFlag(), 1);
    expect(native.lateErrors(), 2);
    expect(native.readLateFlag(), 1);
    expect(native.checkLateBound(0, 42), 42);
    expect(native.checkLateBound(1, 42), -1);
  });

  test(
    'bounded scalars materialize with their original Object type and value',
    () {
      for (final floating in [-0.0, _double(0x7ff8000000000042), 18.25]) {
        native.storeScalars(-0x123456789abc, floating, 1);
        native.observeScalar(0);
        expect(native.observedKind(), 0);
        expect(native.observedInteger(), -0x123456789abc);
        native.observeScalar(1);
        expect(native.observedKind(), 1);
        expect(_bits(native.observedFloating()), _bits(floating));
        native.observeScalar(2);
        expect(native.observedKind(), 2);
        expect(native.observedInteger(), 1);
      }
      native.storeScalars(0, 0.0, 0);
      native.observeScalar(2);
      expect(native.observedKind(), 2);
      expect(native.observedInteger(), 0);
    },
  );

  test('ordinary generic storage retains mixed scalars, null and objects', () {
    for (final kind in [0, 1, 2, 3, 4, 1, 0]) {
      native.storeMixed(kind, -91, -0.0, 19);
      expect(native.observedKind(), kind);
      switch (kind) {
        case 0 || 4:
          expect(native.observedInteger(), -91);
        case 1:
          expect(_bits(native.observedFloating()), _bits(-0.0));
        case 2:
          expect(native.observedInteger(), 1);
        case 3:
          expect(native.observedFloating(), -1.0);
      }
    }
  });

  test(
    'retained scalar equality distinguishes bool and mixed numeric values',
    () {
      for (final (kind, integer, floating, expected) in [
        (0, 42, 42.0, 3),
        (1, 42, 42.0, 3),
        (2, 1, 42.0, 12),
        (2, 0, 42.0, 0),
        (3, 42, 42.0, 0),
        (4, 42, 42.0, 0),
        (1, 42, double.nan, 0),
      ]) {
        native.storeMixed(kind, integer, floating, 7);
        expect(native.scalarEqual(42, 42.0, 1, 11), expected);
      }
    },
  );

  test('num storage retains either numeric representation', () {
    native.storeNumber(0, -73, -0.0);
    expect(native.numberKind(), 0);
    expect(native.numberValue(), -73.0);
    native.storeNumber(1, -73, -0.0);
    expect(native.numberKind(), 1);
    expect(_bits(native.numberValue()), _bits(-0.0));
  });

  test(
    'promoted values keep nominal type arguments and actual record fields',
    () {
      for (final value in [-73, 0, 42]) {
        expect(native.inferredType(0, value), 14);
        expect(native.inferredType(1, value), 15);
        expect(native.inferredType(2, value), 0);
      }
    },
  );

  test('nullable scalar storage preserves null and exact floating payload', () {
    native.storeNullable(0, 12.0);
    expect(native.nullablePresent(), 0);
    native.storeNullable(1, -0.0);
    expect(native.nullablePresent(), 1);
    expect(_bits(native.nullableValue()), _bits(-0.0));
    native.storeNullable(0, -0.0);
    expect(native.nullablePresent(), 0);
  });

  test('retained generic values survive observable allocation pressure', () {
    final nan = _double(0x7ff8000000000042);
    native.storeScalars(-0x123456789abc, -0.0, 1);
    native.storeCaptures(-41, 73, -0.0, nan, 0, 1);
    for (final kind in [0, 1, 2]) {
      native.observeScalar(kind);
      // Every retained node is observed through the next independent entry.
      native.allocatePressure(40000);
      expect(native.pressureSum(), 799980000);
      expect(native.readInteger(17), -0x123456789abc);
      expect(_bits(native.readFloating(17)), _bits(-0.0));
      expect(native.readFlag(17), 1);
      expect(native.observedKind(), kind);
      if (kind == 1) {
        expect(_bits(native.observedFloating()), _bits(-0.0));
      } else {
        expect(native.observedInteger(), kind == 0 ? -0x123456789abc : 1);
      }
      expect(native.capturedInteger(0), kind == 0 ? -41 : 73);
      expect(_bits(native.capturedFloating(0)), _bits(kind == 0 ? -0.0 : nan));
      expect(native.capturedFlag(0), kind == 0 ? 0 : 1);
      expect(native.capturedInteger(1), 73);
      expect(_bits(native.capturedFloating(1)), _bits(nan));
      expect(native.capturedFlag(1), 1);
    }
    native.storeMixed(4, -91, 0.0, 17);
    native.allocatePressure(40000);
    expect(native.pressureSum(), 799980000);
    expect(native.observedKind(), 4);
    expect(native.observedInteger(), -91);
  });
}

int _bits(double value) => (ByteData(
  8,
)..setFloat64(0, value, Endian.little)).getUint64(0, Endian.little);

double _double(int bits) => (ByteData(
  8,
)..setUint64(0, bits, Endian.little)).getFloat64(0, Endian.little);
