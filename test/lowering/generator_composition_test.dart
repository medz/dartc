import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/generator_composition.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(
    () async => fixture = await FixtureComparison.load('generator_composition'),
  );
  for (final (name, expected) in [
    ('ordinaryExtensionGenerators', sdk.ordinaryExtensionGenerators),
    ('extensionTypeGenerators', sdk.extensionTypeGenerators),
    ('genericClassGeneratorCapture', sdk.genericClassGeneratorCapture),
    ('patternGenerator', sdk.patternGenerator),
  ]) {
    test('$name preserves type and receiver environments', () {
      fixture.compare(name, [], expected);
    });
  }
  test('covariant argument checks happen before generator creation', () {
    for (final tearOff in [false, true]) {
      fixture.compare('covariantGeneratorEntry', [
        tearOff,
      ], () => sdk.covariantGeneratorEntry(tearOff));
    }
  });
}
