@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('compiled heap sizing rounds size classes and failure bounds', () {
    final library = NativeAssets(Target.host()).open('compiler/heap_runtime');
    addTearDown(library.close);
    final capacity = library
        .lookupFunction<Int64 Function(Int64), int Function(int)>('capacity');
    const maximum = 0x1000000000000000;
    for (final (needed, expected) in [
      (0, 0),
      (1, 64),
      (64, 64),
      (65, 128),
      (65536, 65536),
      (65537, 131072),
      (maximum - 1, maximum),
      (maximum, maximum),
      (maximum + 1, 0),
      (-1, 0),
    ]) {
      expect(capacity(needed), expected);
    }
  });
}
