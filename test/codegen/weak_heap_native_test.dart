@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'weak slots and ephemeron cycles preserve only independently live keys',
    () {
      final library = NativeAssets(Target.host()).open('codegen/weak_heap');
      addTearDown(library.close);
      for (final name in ['weak', 'ephemeron']) {
        final run = library
            .lookupFunction<Int8 Function(Int8, Int64), int Function(int, int)>(
              name,
            );
        for (final retain in [false, true, false]) {
          expect(run(retain ? 1 : 0, 10000), 1, reason: '$name retain=$retain');
        }
      }
    },
  );
}
