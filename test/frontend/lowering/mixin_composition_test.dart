import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/mixin_composition.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(
    () async => fixture = await FixtureComparison.load('mixin_composition'),
  );
  for (final (name, reference) in <(String, Object? Function())>[
    ('composedGenerators', sdk.composedGenerators),
    ('composedObjectMembers', sdk.composedObjectMembers),
    ('composedUnionTypes', sdk.composedUnionTypes),
  ]) {
    test('$name matches the SDK', () => fixture.compare(name, [], reference));
  }
}
