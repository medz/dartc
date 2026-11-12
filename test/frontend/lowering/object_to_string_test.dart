import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../../support/ir_interpreter.dart';
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
    ('sdkStorageString', sdk.sdkStorageString),
    ('sdkStoragePattern', sdk.sdkStoragePattern),
    ('recordString', sdk.recordString),
  ]) {
    test('$name matches the Dart SDK', () {
      fixture.compare(name, [], expected);
    });
  }
  for (final name in [
    'functionString',
    'setString',
    'mapString',
    'listString',
    'errorString',
  ]) {
    test('$name rejects an unmodeled representation', () {
      final entry = fixture.program.functions.singleWhere(
        (function) => function.target.name == name,
      );
      expect(
        () => IrInterpreter(fixture.program, {}).run(entry, []),
        throwsUnsupportedError,
      );
    });
  }
}
