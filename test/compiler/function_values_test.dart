@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/function_values.dart' as sdk;
import 'fixtures/function_values_ffi.dart';

void main() {
  late FunctionValues native;
  setUpAll(() {
    native = FunctionValues();
    addTearDown(native.close);
  });

  test(
    'static tear-offs retain defaults, identity and references through GC',
    () {
      for (final count in [0, 40000]) {
        expect(native.staticCalls(0, count), 171398);
        expect(native.staticCalls(1, count), 70598);
        expect(native.staticCalls(2, count), 203698);
        expect(native.staticIdentity(count), 1111);
      }
    },
  );

  test('generic function constants retain signatures and type arguments', () {
    for (final count in [0, 40000]) {
      expect(native.genericCalls(count), 2345);
      expect(native.functionTypes(count), 111111);
    }
  });

  test('constructor tear-offs retain aliases, redirects and actual types', () {
    for (final count in [0, 40000]) {
      expect(native.constructors(count), 23465);
      expect(native.constructorIdentity(count), 11111);
    }
  });
  test(
    'redirected constructor values retain defaults and public argument names',
    () {
      for (final count in [0, 40000]) {
        expect(sdk.constructorDefaults(count), 1);
        expect(native.constructorDefaults(count), 1);
      }
    },
  );
  test('indirect void calls and exceptions preserve effects and cleanup', () {
    for (final count in [0, 40000]) {
      expect(native.effects(count), 123409);
    }
  });
}
