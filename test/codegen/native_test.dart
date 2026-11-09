@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/aliases_ffi.dart';
import 'fixtures/control_flow_ffi.dart';

void main() {
  test('arithmetic preserves aliased right operands', () {
    final native = Aliases();
    addTearDown(native.close);
    expect(native.add(40, 2), 42);
    expect(native.subtract(40, 2), 38);
    expect(native.subtract(2, 40), -38);
  });

  test(
    'parallel edges retain distinct argument assignments to the same block',
    () {
      final native = ControlFlowGraphs();
      addTearDown(native.close);
      const values = [-0x8000000000000000, -1, 0, 42, 0x7fffffffffffffff];
      for (final a in values) {
        expect(native.scrambled(a), a + 7 + a);
        expect(native.unusedResult(a, 2, 3, 4, 5, 6), a);
        for (final b in values) {
          expect(native.sameTarget(a, b), a < b ? a - b : b - a);
        }
      }
    },
  );
}
