import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/identity.dart' as sdk;

void main() {
  test(
    'identical resolves by declaration and remains an ordinary function value',
    () async {
      final fixture = await FixtureComparison.load('identity');
      final shared = Object();
      for (final (a, b) in [
        (shared, shared),
        (shared, Object()),
        (null, null),
        (1, 1),
        (1, 1.0),
        (0.0, -0.0),
        (double.nan, double.nan),
      ]) {
        fixture.compare('compare', [a, b], () => sdk.compare(a, b));
        fixture.compare('compareValue', [a, b], () => sdk.compareValue(a, b));
      }
      fixture.compare('shadowed', [shared], () => false);
      final intrinsic = fixture.program.functions.singleWhere(
        (f) =>
            f.target.library == Uri.parse('dart:core') &&
            f.target.name == 'identical',
      );
      final operation = intrinsic.entry.instructions.single as Identical;
      expect(operation.effects, isEmpty);
      expect(operation.inputs, intrinsic.entry.parameters);
    },
  );
}
