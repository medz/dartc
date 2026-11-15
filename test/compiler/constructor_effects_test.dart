@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/constructor_effects.dart' as sdk;
import 'fixtures/constructor_effects_ffi.dart';

void main() {
  test('generic constructors preserve state across normal, failed and void ABI calls', () {
    final native = ConstructorEffects();
    addTearDown(native.close);
    for (final depth in [0, 1, 2, 99, 100]) {
      expect(native.recoverDepth(depth), sdk.recoverDepth(depth));
    }
    for (final value in [-0x8000000000000000, 0, 42, 0x7fffffffffffffff]) {
      for (final fail in [false, true]) {
        expect(native.construct(value, fail), sdk.construct(value, fail));
        expect(native.count(), sdk.count());
        sdk.remember(value);
        native.remember(value);
        expect(native.count(), sdk.count());
      }
    }
  });
}
