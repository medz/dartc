@Tags(['assets', 'native'])
library;

import 'dart:ffi';

import 'package:dartc/layout.dart';
import 'package:test/test.dart';

import 'fixtures/stack_roots_ffi.dart';

void main() {
  test(
    'suspended callers reload updated roots across native and Dart frames',
    () {
      final native = StackRootCalls();
      addTearDown(native.close);
      final maps = <int, StackRoots>{};
      var offset = 1;
      for (var i = 0; i < native.table.value; i++) {
        final count = native.table[offset + 3];
        maps[native.table[offset]] = StackRoots(
          native.table[offset + 1],
          native.table[offset + 2],
          [for (var j = 0; j < count; j++) native.table[offset + 4 + j]],
        );
        offset += 4 + count;
      }
      for (final route in [0, 1]) {
        for (final relocate in [false, true, true]) {
          final frames = <int>[], visited = <int>{};
          var changed = 0, nulls = 0;
          final visitor = NativeCallable<RootVisitor>.isolateLocal((
            int pc,
            Pointer<Uint64> sp,
          ) {
            for (var depth = 0; depth < 10; depth++) {
              final roots = maps[pc];
              expect(roots, isNotNull, reason: 'Missing return PC: $pc');
              if (roots == null) return -1;
              frames.add(roots.offsets.length);
              for (final bytes in roots.offsets) {
                final slot = sp + bytes ~/ 8;
                expect(visited.add(slot.address), isTrue);
                if (slot.value == 0) {
                  nulls++;
                } else {
                  expect(slot.value, native.original.address);
                  if (relocate) slot.value = native.replacement.address;
                  changed++;
                }
              }
              if (roots.callerStackOffset == 0) return 5;
              pc = sp[roots.returnAddressOffset ~/ 8];
              sp += roots.callerStackOffset ~/ 8;
            }
            fail('Stack walk did not reach a native entry.');
          }, exceptionalReturn: -1);
          try {
            final result = native.run(
              native.probe.address,
              visitor.nativeFunction.address,
              native.original.address,
              route,
            );
            expect(
              result,
              12 * (relocate ? 99 : 41) + 5 + 2 * native.original.address,
            );
            expect(frames, [if (route == 0) 0, 0, 9, 4, 0]);
            expect(changed, 12);
            expect(nulls, 1);
          } finally {
            visitor.close();
          }
        }
      }
    },
  );
}
