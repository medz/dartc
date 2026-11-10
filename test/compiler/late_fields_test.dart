@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/late_fields_ffi.dart';

void main() {
  late LateFields native;
  setUpAll(() {
    native = LateFields();
    addTearDown(native.close);
  });

  test(
    'instance and inherited slots stay isolated; constructor writes bind',
    () {
      expect(native.isolation(), 222);
      expect(native.nullableBinding(), 7);
    },
  );

  test(
    'lazy retries, committed writes and recursive bindings survive failure',
    () {
      expect(native.initialization(), 1);
      expect(native.writeOrdering(), 425);
    },
  );

  test('initializers receive actual inherited type arguments', () {
    expect(native.genericEnvironment(), 2);
  });

  test('normative safety: late final checks actual type before binding', () {
    // Intentionally not an SDK comparison; see specs/variables.md.
    expect(native.genericFinalSafety(), 42);
  });

  test('receiver and returned references survive GC, rethrow and finally', () {
    expect(native.references(40000), 1234);
    expect(native.references(1), 1234);
  });
}
