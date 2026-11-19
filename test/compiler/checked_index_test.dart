@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('checked index preserves the check count across a caught throw', () {
    final library = NativeAssets(Target.host()).open('compiler/checked_index');
    addTearDown(library.close);
    final checkedIndex = library
        .lookupFunction<Int64 Function(Int64, Bool), int Function(int, bool)>(
          'checkedIndex',
        );

    expect(checkedIndex(6, true), 7);
    expect(checkedIndex(-4, true), 81);
    expect(checkedIndex(-4, false), -4);
  });
}
