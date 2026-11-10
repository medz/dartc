@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/dynamic_boxes_ffi.dart';

void main() {
  test('runtime scalars retain every bit through allocating transfers', () {
    final boxes = DynamicBoxes();
    addTearDown(boxes.close);
    for (final operation in [
      'return',
      'call',
      'edge',
      'view',
      'initial',
      'write',
      'field',
      'construct',
      'generic',
      'generic_construct',
    ]) {
      for (final value in [
        -0x8000000000000000,
        0x7fffffffffffffff,
        -1,
        0,
        42,
      ]) {
        expect(boxes.integer(operation, value), value, reason: operation);
      }
      for (final bits in [
        0,
        0x8000000000000000,
        1,
        0x3ff4000000000000,
        0x7ff0000000000000,
        0xfff0000000000000,
        0x7ff8000000000001,
        0x7ff8000000000002,
      ]) {
        final data = ByteData(8)..setUint64(0, bits);
        final result = boxes.floating(operation, data.getFloat64(0));
        expect(
          (data..setFloat64(0, result)).getUint64(0),
          bits,
          reason: operation,
        );
      }
    }
  });

  test(
    'partially staged arguments and incoming stack references survive GC',
    () {
      final boxes = DynamicBoxes();
      addTearDown(boxes.close);
      for (final count in [0, 4090, 4094, 8190, 40000]) {
        expect(boxes.collect(70, count), 745, reason: '$count');
      }
    },
  );
}
