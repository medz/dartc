@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'fixtures/type_checks.dart' as sdk;
import 'fixtures/type_checks_ffi.dart';

void main() {
  test(
    'checked casts and null assertions preserve results and throw TypeError',
    () {
      final native = TypeChecks();
      addTearDown(native.close);
      for (var mode = 0; mode < 16; mode++) {
        for (final seed in [-123, 0, 456]) {
          for (final count in [0, 40000]) {
            expect(
              native.castInteger(mode, seed, count),
              sdk.castInteger(mode, seed, count),
              reason: '$mode, $seed, $count',
            );
            expect(
              native.castDouble(mode, seed, count),
              sdk.castDouble(mode, seed, count),
              reason: '$mode, $seed, $count',
            );
          }
          for (var kind = 0; kind < 9; kind++) {
            expect(
              native.castKinds(mode, seed, kind),
              sdk.castKinds(mode, seed, kind),
              reason: '$mode, $seed, kind $kind',
            );
          }
        }
        expect(
          native.dynamicThrow(mode),
          sdk.dynamicThrow(mode),
          reason: 'throw $mode',
        );
      }
      for (final bits in [
        0x8000000000000000,
        0x7ff8000000000001,
        1,
        0x7ff0000000000000,
      ]) {
        final value = (ByteData(8)..setUint64(0, bits)).getFloat64(0);
        expect(
          (ByteData(8)..setFloat64(0, native.castFloating(value))).getUint64(0),
          bits,
        );
      }
    },
  );

  test(
    'cast failure retains evaluation order, rethrow and finally effects',
    () {
      final native = TypeChecks();
      addTearDown(native.close);
      for (final count in [0, 40000]) {
        for (var mode = 0; mode < 16; mode++) {
          native.effects.value = 0;
          final expected = sdk.castCleanup(mode, count, native.effects);
          final effects = native.effects.value;
          native.effects.value = 0;
          expect(
            native.castCleanup(mode, count, native.effects),
            expected,
            reason: '$mode, $count',
          );
          expect(native.effects.value, effects, reason: '$mode, $count');
        }
      }
    },
  );

  test('actual types, promotions and ordered catches match Dart', () {
    final native = TypeChecks();
    addTearDown(native.close);
    for (final count in [0, 40000]) {
      for (var mode = 0; mode < 16; mode++) {
        for (final seed in [-123, 0, 456]) {
          final reason = 'mode $mode, seed $seed, count $count';
          expect(
            native.classify(mode, seed, count),
            sdk.classify(mode, seed, count),
            reason: reason,
          );
          expect(
            native.promoted(mode, seed),
            sdk.promoted(mode, seed),
            reason: reason,
          );
          expect(
            native.caught(mode, seed, count),
            sdk.caught(mode, seed, count),
            reason: reason,
          );
        }
      }
    }
  });
}
