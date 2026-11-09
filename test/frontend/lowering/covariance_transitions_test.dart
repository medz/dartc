import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/covariance_transitions.dart' as sdk;

void main() {
  test(
    'inherited covariance retains defaults, checks and tearoff types',
    () async {
      final fixture = FixtureComparison(
        await AnalysisSession([
          'test/frontend/lowering/fixtures/covariance_transitions.dart',
          'test/frontend/lowering/fixtures/covariance_transitions_private.dart',
        ]).use((input) async => (await Lowering().lower(input)).program),
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
