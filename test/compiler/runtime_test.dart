@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'compiled heap sizing retains exact large capacities and failure bounds',
    () {
      final library = NativeAssets(Target.host())
          .open('compiler/heap_capacity');
      addTearDown(library.close);
      final capacity = library
          .lookupFunction<Int64 Function(Int64, Int64), int Function(int, int)>(
            'capacity',
          );
      const maximum = 0x2000000000000000;
      for (final (current, needed, expected) in [
        (0, 0, 65536),
        (0, 65537, 131072),
        (131072, 65536, 131072),
        (65536, maximum - 1, maximum),
        (maximum - 1, maximum, maximum),
        (maximum, maximum, maximum),
        (maximum, maximum + 1, 0),
        (-1, 0, 0),
        (0, -1, 0),
        (maximum + 1, 0, 0),
      ]) {
        expect(capacity(current, needed), expected);
      }
    },
  );
}
