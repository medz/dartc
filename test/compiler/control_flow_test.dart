@Tags(['assets', 'native'])
library;

import 'package:test/test.dart';

import 'fixtures/control_flow.dart' as sdk;
import 'fixtures/control_flow_ffi.dart';

void main() {
  late ControlFlow native;
  setUpAll(() {
    native = ControlFlow();
    addTearDown(native.close);
  });

  test(
    'signed comparisons, boolean results and multiple returns match the SDK',
    () {
      const values = [
        -0x8000000000000000,
        -42,
        -1,
        0,
        1,
        42,
        0x7fffffffffffffff,
      ];
      for (final a in values) {
        for (final b in values) {
          expect(
            native.choose(a, b),
            sdk.choose(a, b),
            reason: 'choose($a, $b)',
          );
          expect(
            native.conditional(a, b),
            sdk.conditional(a, b),
            reason: 'conditional($a, $b)',
          );
          expect(
            native.relations(a, b),
            sdk.relations(a, b),
            reason: 'relations($a, $b)',
          );
          expect(
            native.shortCircuit(a, b),
            sdk.shortCircuit(a, b),
            reason: 'shortCircuit($a, $b)',
          );
        }
      }
    },
  );

  test('loop entries, backedges, break, continue and simultaneous assignments match the SDK', () {
    for (var limit = -2; limit <= 20; limit++) {
      expect(
        native.nestedTransfers(limit),
        sdk.nestedTransfers(limit),
        reason: 'nested($limit)',
      );
      expect(
        native.whileLoop(limit),
        sdk.whileLoop(limit),
        reason: 'while($limit)',
      );
      expect(native.doLoop(limit), sdk.doLoop(limit), reason: 'do($limit)');
      expect(native.forLoop(limit), sdk.forLoop(limit), reason: 'for($limit)');
      expect(native.rotate(limit), sdk.rotate(limit), reason: 'rotate($limit)');
      expect(
        native.loopCalls(limit),
        sdk.loopCalls(limit),
        reason: 'calls($limit)',
      );
      expect(
        native.foreverWithExit(limit),
        sdk.foreverWithExit(limit),
        reason: 'exit($limit)',
      );
    }
  });

  test('recursive returns preserve the first result across a second recursive call', () {
    for (var value = -1; value <= 12; value++) {
      expect(native.recursive(value), sdk.recursive(value), reason: '$value');
    }
  });
}
