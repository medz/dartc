import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/generic_redirect_factory.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('generic_redirect_factory');
  });

  test(
    'generic redirect chains preserve types, defaults and evaluation order',
    () {
      for (final seed in [-1, 0, 4]) {
        for (var mode = 0; mode < 6; mode++) {
          fixture.compare('genericRedirect', [
            seed,
            mode,
          ], () => sdk.genericRedirect(seed, mode));
        }
      }
    },
  );

  test('generic redirect tearoffs instantiate arguments and defaults', () {
    for (final seed in [-1, 0, 4]) {
      for (var mode = 0; mode < 6; mode++) {
        fixture.compare('genericRedirectTearoff', [
          seed,
          mode,
        ], () => sdk.genericRedirectTearoff(seed, mode));
      }
      fixture.compare('genericRedirectBounds', [
        seed,
      ], () => sdk.genericRedirectBounds(seed));
      fixture.compare('genericRedirectEnvironment', [
        seed,
      ], () => sdk.genericRedirectEnvironment(seed));
    }
  });

  test('redirect tearoffs retain source and applied owner identity', () {
    fixture.compare('genericRedirectIdentity', [], sdk.genericRedirectIdentity);
  });

  test('redirect resolution validates destination and source bounds', () {
    final source = fixture.program.classes.singleWhere(
      (c) => c.type.name == 'NumberRedirect',
    );
    final ctor = source.constructors.values.single;
    final valid = ctor.resolveConstruction(
      source.type.instantiate([ValueType.integer]),
    );
    expect(valid.target.owner!.name, 'NumberConcrete');
    expect(valid.ownerType.typeArguments, [ValueType.integer]);
    expect(
      () =>
          ctor.resolveConstruction(source.type.instantiate([ValueType.string])),
      throwsArgumentError,
    );
  });
}
