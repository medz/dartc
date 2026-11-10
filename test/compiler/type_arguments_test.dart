@Tags(['assets', 'native'])
library;

import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/type_arguments.dart' as sdk;
import 'fixtures/type_arguments_ffi.dart';

void main() {
  test('actual runtime types survive boxing, constants and collection', () {
    final native = TypeArguments();
    addTearDown(native.close);
    for (final count in [0, 40000]) {
      for (var mode = 0; mode < 24; mode++) {
        expect(sdk.runtimeTypes(mode, count), 3, reason: 'SDK: $mode');
        expect(native.runtimeTypes(mode, count), 3, reason: '$mode, $count');
      }
    }
  });
  test('function bounds normalize from actual arguments across GC', () {
    final native = TypeArguments();
    addTearDown(native.close);
    for (final count in [0, 40000]) {
      for (var mode = 0; mode < 18; mode++) {
        final expected = mode == 2 ? 0 : 1;
        expect(native.bounds(mode, count), expected, reason: '$mode, $count');
        // SDK 3.13.7 leaves mode 10's closed nested literal unnormalized; see specs/types.md.
        if (mode != 10) {
          expect(sdk.bounds(mode, count), expected, reason: 'SDK: $mode');
        }
      }
    }
  });

  test('reified arguments survive forwarding, recursion, stacks and GC', () {
    final native = TypeArguments();
    addTearDown(native.close);
    for (final count in [0, 40000]) {
      for (final depth in [0, 7]) {
        for (var mode = 0; mode < 14; mode++) {
          expect(
            native.types(mode, depth, count),
            sdk.types(mode, depth, count),
            reason: '$mode, $depth, $count',
          );
        }
        expect(
          native.stack(-23, 91, 1.5, depth, count),
          sdk.stack(-23, 91, 1.5, depth, count),
        );
      }
    }
  });

  test('generic calls preserve scalar argument and result representations', () {
    final native = TypeArguments();
    addTearDown(native.close);
    for (final count in [0, 40000]) {
      for (final value in [-0x8000000000000000, -1, 0, 0x7fffffffffffffff]) {
        expect(native.integer(value, count), sdk.integer(value, count));
      }
      for (final bits in [0x8000000000000000, 0x7ff8000000000001, 1]) {
        final value = (ByteData(8)..setUint64(0, bits)).getFloat64(0);
        expect(
          (ByteData(
            8,
          )..setFloat64(0, native.floating(value, count))).getUint64(0),
          bits,
        );
      }
    }
  });

  test(
    'runtime type structures normalize and preserve lexical binders across GC',
    () {
      final native = TypeArguments();
      addTearDown(native.close);
      for (final count in [0, 40000]) {
        for (var mode = 0; mode < 30; mode++) {
          final expected = {19, 22, 24, 25}.contains(mode) ? 0 : 1;
          expect(sdk.structures(mode, count), expected, reason: 'SDK: $mode');
          expect(
            native.structures(mode, count),
            expected,
            reason: '$mode, $count',
          );
        }
      }
    },
  );
}
