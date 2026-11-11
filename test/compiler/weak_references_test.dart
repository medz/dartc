@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/weak_references.dart' as sdk;
import 'fixtures/weak_references_ffi.dart';

void main() {
  test(
    'weak targets survive strong roots and clear after the roots are released',
    () {
      final native = WeakReferences();
      addTearDown(native.close);
      for (final retain in [0, 1, 0]) {
        native.create(3.25, retain);
        expect(native.read(), 3.25);
        expect(native.churn(20000), 199990000);
        expect(native.read(), retain == 0 ? -1 : 3.25);
        expect(native.readOther(), -1);
        native.release();
        native.churn(20000);
        expect(native.read(), -1);
      }
      native.create(7.5, 1);
      expect(native.retainRead(20000), 7.5);
      native.churn(20000);
      expect(native.read(), -1);
    },
  );

  test(
    'generic factories preserve local roots, type arguments and constants',
    () {
      final native = WeakReferences();
      addTearDown(native.close);
      for (final value in [1.25, -0.0, double.infinity]) {
        final expected = sdk.local(value, 20000);
        expect(native.local(value, 20000), expected);
        expect(1 / native.local(value, 0), 1 / expected);
      }
      expect(native.constantTarget(20000), sdk.constantTarget(20000));
      expect(native.constantTarget(20000), 42);
      expect(native.objectKinds(20000), sdk.objectKinds(20000));
      expect(native.objectKinds(0), 1);
    },
  );

  test(
    'unsupported target values raise ArgumentError with their original value',
    () {
      final native = WeakReferences();
      addTearDown(native.close);
      for (var kind = 0; kind < 5; kind++) {
        expect(sdk.rejects(kind), 1);
        expect(native.rejects(kind), 1, reason: 'kind=$kind');
      }
    },
  );
}
