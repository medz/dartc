@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/late_locals.dart' as sdk;
import 'fixtures/late_locals_ffi.dart';

void main() {
  late LateLocals native;
  setUpAll(() {
    native = LateLocals();
    addTearDown(native.close);
  });

  for (final (mode, name, expected) in [
    (0, 'unbound and final writes preserve null and RHS effects', 7),
    (
      1,
      'lazy initialization retries and retains the first successful value',
      15,
    ),
    (2, 'recursive final initialization preserves the inner binding', 3),
    (3, 'initializer failure retains writes and success replaces them', 6),
    (
      4,
      'generic cells check values before binding and retain lexical types',
      93,
    ),
    (5, 'loop bindings retain independent values and initialization states', 7),
    (6, 'null binds once and Never initializers retry on every read', 15),
    (9, 'late cells preserve floating and boolean representations', 3),
    (10, 'mutable recursive initialization keeps the outer result', 1),
  ]) {
    test(name, () {
      for (final count in [0, 10000]) {
        expect(sdk.lateLocals(mode, count), expected);
        expect(native.call(mode, count), expected);
      }
    });
  }

  test('lazy captures survive their creator and subsequent native entries', () {
    for (final count in [0, 10000]) {
      expect(sdk.lateLocals(7, count), 1);
      expect(native.call(7, count), 1);
      for (var i = 0; i < 2; i++) {
        expect(sdk.lateLocals(8, count), 18);
        expect(native.call(8, count), 18);
      }
    }
  });
}
