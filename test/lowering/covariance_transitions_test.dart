import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/covariance_transitions.dart' as sdk;

void main() {
  test(
    'inherited covariance retains defaults, checks and tearoff types',
    () async {
      final fixture = FixtureComparison(
        await CheckedLibraries.read([
          'test/lowering/fixtures/covariance_transitions.dart',
          'test/lowering/fixtures/covariance_transitions_private.dart',
        ], Lowering.lower),
      );
      fixture.compare('defaults', [], sdk.defaults);
      fixture.compare('tearoffs', [], sdk.tearoffs);
      fixture.compare('privateDispatch', [], sdk.privateDispatch);
      for (var kind = 0; kind < 6; kind++) {
        for (final argument in [null, 3, 1.5, 'bad']) {
          fixture.compare('call', [
            kind,
            argument,
          ], () => sdk.call(kind, argument));
        }
      }
      for (final argument in [null, 3, 1.5, 'bad']) {
        fixture.compare('operations', [
          argument,
        ], () => sdk.operations(argument));
      }
    },
  );
}
