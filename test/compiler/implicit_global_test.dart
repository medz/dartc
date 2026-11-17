@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('implicit-null storage persists between native entries', () {
    final library = NativeAssets(Target.host())
        .open('compiler/implicit_global');
    addTearDown(library.close);
    final read = library.lookupFunction<Int64 Function(), int Function()>(
      'readRetained',
    );
    final write = library
        .lookupFunction<Void Function(Int64), void Function(int)>(
          'writeRetained',
        );

    expect(read(), -1);
    for (final (input, expected) in [(0, 0), (42, 1), (-7, -1), (0, 0)]) {
      write(input);
      expect(read(), expected);
    }
  });
}
