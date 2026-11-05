import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixture_runner.dart';
import 'fixtures/object_to_string.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(
    () async => fixture = await FixtureComparison.load('object_to_string'),
  );
  for (final (name, expected) in <(String, Object Function())>[
    ('plainStrings', sdk.plainStrings),
    ('overrideStrings', sdk.overrideStrings),
    ('superStrings', sdk.superStrings),
    ('scalarStrings', sdk.scalarStrings),
    ('tearOffIdentity', sdk.tearOffIdentity),
    ('patternString', sdk.patternString),
    ('enumStrings', sdk.enumStrings),
    ('overrideTearOffIdentity', sdk.overrideTearOffIdentity),
    ('symbolTearOffIdentity', sdk.symbolTearOffIdentity),
  ]) {
    test('$name matches the Dart SDK', () {
      fixture.compare(name, [], expected);
    });
  }
  for (final name in [
    'functionString',
    'setString',
    'mapString',
    'recordString',
    'listString',
    'errorString',
    'sdkStorageString',
    'sdkStoragePattern',
  ]) {
    test('$name rejects an unmodeled representation', () {
      final entry = fixture.program.functions.singleWhere(
        (function) => function.target.name == name,
      );
      expect(
        () => FixtureRunner(fixture.program, {}).run(entry, []),
        throwsUnsupportedError,
      );
    });
  }
}
