import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/generic_semantics.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('generic_semantics');
  });

  test('generic patterns, aliases and contextual constructors match Dart', () {
    for (final seed in [-2, 0, 1, 7]) {
      for (final (name, function) in <(String, Object? Function(int))>[
        ('genericObjectPattern', sdk.genericObjectPattern),
        ('genericBodyPattern', sdk.genericBodyPattern),
        ('genericNullablePattern', sdk.genericNullablePattern),
        ('genericRecordCache', sdk.genericRecordCache),
        ('genericRecordPattern', sdk.genericRecordPattern),
        ('genericGetterCache', sdk.genericGetterCache),
        ('genericAlias', sdk.genericAlias),
        ('genericDotConstructor', sdk.genericDotConstructor),
        ('genericInterfaceTests', sdk.genericInterfaceTests),
        ('genericInterfacePattern', sdk.genericInterfacePattern),
        ('genericTextJoin', sdk.genericTextJoin),
      ]) {
        fixture.compare(name, [seed], () => function(seed));
      }
      for (final valid in [false, true]) {
        fixture.compare('genericInterfaceCast', [
          seed,
          valid,
        ], () => sdk.genericInterfaceCast(seed, valid));
      }
    }
  });
}
