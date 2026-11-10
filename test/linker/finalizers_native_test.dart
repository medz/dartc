@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test('finalizers run once at last close, including an archived owner', () {
    final process = DynamicLibrary.process();
    final allocate = process
        .lookupFunction<
          Pointer<Int64> Function(IntPtr, IntPtr),
          Pointer<Int64> Function(int, int)
        >('calloc');
    final free = process
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('free');
    final marker = allocate(2, 8);
    try {
      for (final asset in ['finalizers', 'finalizers_archive']) {
        for (final sharedCounter in [false, true, false]) {
          marker[0] = marker[1] = 0;
          final assets = NativeAssets(Target.host());
          final first = assets.open('linker/$asset');
          final second = assets.open('linker/$asset');
          var firstClosed = false, secondClosed = false;
          try {
            for (var i = 0; i < 2; i++) {
              first.lookup<Pointer<Int64>>('marker_$i').value =
                  marker + (sharedCounter ? 0 : i);
            }
            expect(marker.asTypedList(2), [0, 0]);
            first.close();
            firstClosed = true;
            expect(marker.asTypedList(2), [0, 0]);
            second.close();
            secondClosed = true;
            expect(marker.asTypedList(2), sharedCounter ? [21, 0] : [1, 2]);
          } finally {
            if (!firstClosed) first.close();
            if (!secondClosed) second.close();
          }
        }
      }
    } finally {
      free(marker.cast());
    }
  });
}
