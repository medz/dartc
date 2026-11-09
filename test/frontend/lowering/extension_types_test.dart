import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import '../../support/ir_interpreter.dart';
import 'fixtures/extension_types.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_types');
  });
  test('erased members and construction match SDK values and effects', () {
    for (final (name, function) in <(String, int Function(int))>[
      ('shorthand', sdk.shorthand),
      ('dynamicRepresentation', sdk.dynamicRepresentation),
      ('genericContext', sdk.genericContext),
      ('basic', sdk.basic),
      ('captures', sdk.captures),
      ('updates', sdk.updates),
      ('statics', sdk.statics),
      ('record', sdk.record),
      ('functions', sdk.functions),
      ('nested', sdk.nested),
      ('constructors', sdk.constructors),
      ('cascades', sdk.cascades),
    ]) {
      for (final seed in [0, 3, 7]) {
        fixture.compare(name, [seed], () => function(seed));
      }
    }
    for (final seed in <int?>[null, 0, 3]) {
      fixture.compare('nullable', [seed], () => sdk.nullable(seed));
    }
    for (final value in <int?>[null, 2]) {
      fixture.compare('optionalNullAware', [
        value,
      ], () => sdk.optionalNullAware(value));
    }
    for (final absent in [true, false]) {
      fixture.compare('nullAware', [absent], () => sdk.nullAware(absent));
    }
    fixture.compare('identity', [3], () => sdk.identity(3));
    fixture.compare('constants', [], sdk.constants);
    fixture.compare('moreConstants', [], sdk.moreConstants);
    fixture.compare('constructorIdentity', [], sdk.constructorIdentity);
    fixture.compare('aliasIdentity', [], sdk.aliasIdentity);
    fixture.compare('typeValues', [], sdk.typeValues);
    fixture.compare('nestedTypes', [], sdk.nestedTypes);
    for (final value in <Object?>[null, 2, 'bad']) {
      fixture.compare('checks', [value], () => sdk.checks(value));
      fixture.compare('casts', [value], () => sdk.casts(value));
      fixture.compare('checkedConstruction', [
        value,
      ], () => sdk.checkedConstruction(value));
      fixture.compare('patterns', [value], () => sdk.patterns(value));
    }
  });
  test(
    'extension types do not allocate nominal storage or virtual members',
    () {
      expect(fixture.program.classes, isEmpty);
      final operations = fixture.program.functions
          .expand((f) => f.blocks)
          .expand((b) => b.instructions);
      expect(operations.whereType<Construct>(), isEmpty);
      expect(operations.whereType<LoadField>(), isEmpty);
      expect(
        operations.whereType<InstanceCall>().where(
          (c) => c.member.name.startsWith('<extension-type:'),
        ),
        isEmpty,
      );
    },
  );
  test(
    'imported extension types erase without requiring their bodies',
    () async {
      const entry =
          'test/frontend/lowering/fixtures/extension_type_import.dart';
      final imported = await AnalysisSession([entry])
          .use((input) => Lowering().lower(input).program);
      expect(imported.classes, isEmpty);
      final keep = imported.functions.singleWhere(
        (f) => f.target.name == 'keep',
      );
      expect(keep.target.returnType, ValueType.integer);
      final run = imported.functions.singleWhere((f) => f.target.name == 'run');
      expect(
        run.callees.where((t) => imported.implementationOf(t) == null),
        hasLength(2),
      );
      final linked = await AnalysisSession([
        entry,
        'test/frontend/lowering/fixtures/deferred_library.dart',
      ]).use((input) => Lowering().lower(input).program);
      expect(
        IrInterpreter(
          linked,
          {},
        ).run(linked.functions.singleWhere((f) => f.target.name == 'run'), []),
        3,
      );
    },
  );
}
