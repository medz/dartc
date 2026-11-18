@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'a retained generic capture aliases the same slot across native calls',
    () {
      final library = NativeAssets(Target.host())
          .open('compiler/generic_cell_storage');
      addTearDown(library.close);
      final install = library
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'installCell',
          );
      final write = library
          .lookupFunction<Void Function(Int64, Int64), void Function(int, int)>(
            'writeCell',
          );
      final read = library.lookupFunction<Double Function(), double Function()>(
        'readCell',
      );
      final local = library
          .lookupFunction<Int64 Function(Int64), int Function(int)>(
            'localRoundTrip',
          );
      install(-19);
      expect(read(), -19.0);
      for (final (value, fractional) in [(2, 1), (42, 0), (-8, 1), (50, 0)]) {
        write(value, fractional);
        expect(read(), value + fractional * 0.5);
      }
      expect(local(83), 83);
    },
  );
}
