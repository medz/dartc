import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/mixins.dart' as sdk;

void main() {
  group('fieldless mixin SDK comparison', () {
    late FixtureComparison fixture;
    setUpAll(() async {
      fixture = FixtureComparison(
        await AnalysisSession([
          'test/lowering/fixtures/mixins.dart',
          'test/lowering/fixtures/mixins_private.dart',
        ]).use((input) => Lowering().lower(input).program),
      );
    });

    test('applications contain ordinary independently verified bodies', () {
      final program = fixture.program;
      final targets = program.classes
          .where((c) => c.type.name.contains(':mixin:'))
          .expand((c) => c.members.values)
          .where((m) => m.name == 'add')
          .toList();
      expect(targets.length, greaterThan(1));
      for (final target in targets) {
        expect(
          program.functions.where((f) => f.target == target),
          hasLength(1),
        );
      }
      expect(
        program.functions.where((f) => f.target.owner?.name == 'First'),
        isEmpty,
      );
    });

    for (final (name, reference) in <(String, Object? Function())>[
      ('overrideOrder', sdk.overrideOrder),
      ('superMembers', sdk.superMembers),
      ('interfaceDispatch', sdk.interfaceDispatch),
      ('dynamicMembers', sdk.dynamicMembers),
      ('tearoffs', sdk.tearoffs),
      ('aliasConstructors', sdk.aliasConstructors),
      ('aliasConstructorTearoffs', sdk.aliasConstructorTearoffs),
      ('privateMembers', sdk.privateMembers),
      ('missingMembers', sdk.missingMembers),
      ('mixinClass', sdk.mixinClass),
    ]) {
      test('$name matches the SDK', () => fixture.compare(name, [], reference));
    }
  });
}
