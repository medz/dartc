@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('generic scalar and shared calls preserve both runtime operands', () {
    final library = NativeAssets(Target.host())
        .open('compiler/generic_member_carriers');
    addTearDown(library.close);
    final select = library
        .lookupFunction<
          Int64 Function(Int64, Int64, Int64, Int64),
          int Function(int, int, int, int)
        >('selectWord');
    for (final mode in [0, 1]) {
      for (final (first, next) in [(13, -72), (-97, 4209)]) {
        for (final depth in [0, 1, 2, 5]) {
          expect(select(mode, first, next, depth), depth.isOdd ? next : first);
        }
      }
    }
  });
}
