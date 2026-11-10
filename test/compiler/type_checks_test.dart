@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/type_checks.dart' as sdk;
import 'fixtures/type_checks_ffi.dart';

void main() {
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
