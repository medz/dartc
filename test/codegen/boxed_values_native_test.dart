@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/boxed_values_ffi.dart';

void main() {
  test(
    'refinement retains the original reference alongside its scalar value',
    () {
      final values = BoxedValues();
      addTearDown(values.close);
      expect(values.refinedInteger(0), 21);
      expect(1 / values.refinedFloating(0), double.negativeInfinity);
      expect(values.refinedInteger(1), 13);
      expect(values.refinedFloating(1), 13.0);
      expect(values.pointerIsNull(0), 0);
      expect(values.pointerIsNull(0x1000), 0);
    },
  );

  test('boxed scalar bits survive generic fields, calls, stack arguments and loops', () {
    final values = BoxedValues();
    addTearDown(values.close);
    for (final (i, value) in [
      -0x8000000000000000,
      0x7fffffffffffffff,
      0,
    ].indexed) {
      expect(values.integer(i), value);
    }
    for (final (i, bits) in [
      0x8000000000000000,
      0x7ff8000000000001,
      0x7ff8000000000002,
      0xfff8000000000001,
      1,
      0x7ff0000000000000,
    ].indexed) {
      expect(
        (ByteData(8)..setFloat64(0, values.floating(i))).getUint64(0),
        bits,
      );
    }
    expect(values.boolean(0), 0);
    expect(values.boolean(1), 1);
    expect(values.discard(), 7);
    for (final input in [-1, 0, 1, 2]) {
      expect(values.runtimeBoolean(input), input > 0 ? 1 : 0);
    }
    for (final count in [0, 1, 2, 19, 20]) {
      expect(values.stack(count), count.isEven ? 0.5 : -0.0);
      if (count.isOdd) expect(1 / values.stack(count), double.negativeInfinity);
    }
    for (final operation in ['return', 'view', 'edge', 'initial', 'write']) {
      expect(values.isNull(operation), 0, reason: operation);
    }
    for (final operation in [
      'return',
      'view',
      'edge',
      'initial',
      'write',
      'call',
    ]) {
      expect(
        1 / values.unboxFloating(operation),
        double.negativeInfinity,
        reason: operation,
      );
      expect(
        values.unboxInteger(operation),
        0x7fffffffffffffff,
        reason: operation,
      );
    }
  });
}
