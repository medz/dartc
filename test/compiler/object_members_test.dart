@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/object_members.dart' as sdk;
import 'fixtures/object_members_ffi.dart';

void main() {
  test(
    'runtimeType overrides and Type equality preserve effects and roots',
    () {
      final native = ObjectMembers();
      addTearDown(native.close);
      for (final count in [0, 10000]) {
        for (final (mode, expected) in [255, 255, 255, 255, 7].indexed) {
          expect(sdk.objectMembers(mode, count), expected);
          expect(native.call(mode, count), expected, reason: '$mode, $count');
        }
      }
    },
  );
}
