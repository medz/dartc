import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/dynamic_throw.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('dynamic_throw');
  });

  for (final (name, function) in <(String, Object? Function(dynamic))>[
    ('direct', sdk.direct),
    ('withFinally', sdk.withFinally),
    ('caught', sdk.caught),
    ('rethrowIdentity', sdk.rethrowIdentity),
    ('operandFailure', sdk.operandFailure),
    ('finallyOverrides', sdk.finallyOverrides),
  ]) {
    test('$name matches SDK dynamic throw conversion and effects', () {
      for (final value in <Object?>['exception', 7, Object(), null]) {
        fixture.compare(name, [value], () => function(value));
      }
    });
  }
}
