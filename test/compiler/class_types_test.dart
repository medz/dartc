@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/class_types.dart' as sdk;
import 'fixtures/class_types_ffi.dart';

void main() {
  test('constructors and factories preserve class environments across inheritance and GC', () {
    final native = ClassTypes();
    addTearDown(native.close);
    final nan = (ByteData(8)..setUint64(0, 0x7ff8000000000001)).getFloat64(0);
    for (final count in [0, 10000]) {
      for (final word in [-0x8000000000000000, 0x7fffffffffffffff]) {
        for (final number in [-0.0, nan]) {
          for (var mode = 0; mode < 6; mode++) {
            expect(sdk.classTypes(mode, word, number, count), 15);
            expect(
              native.call(mode, word, number, count),
              15,
              reason: '$mode, $word, $number, $count',
            );
          }
        }
      }
    }
  });
}
