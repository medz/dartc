import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixtures/extension_call.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_call');
  });

  test(
    'ordinary extension call preserves values and receiver/getter order',
    () {
      for (final (name, function) in <(String, Object? Function(int))>[
        ('direct', sdk.direct),
        ('virtualGetter', sdk.virtualGetter),
        ('parenthesizedGetter', sdk.parenthesizedGetter),
        ('extensionGetter', sdk.extensionGetter),
        ('explicitGetter', sdk.explicitGetter),
        ('explicit', sdk.explicit),
        ('lexical', sdk.lexical),
        ('generic', sdk.generic),
        ('genericGetters', sdk.genericGetters),
        ('retainedType', sdk.retainedType),
      ]) {
        for (final seed in [0, 3, 7]) {
          fixture.compare(name, [seed], () => function(seed));
        }
      }
      fixture.compare('topGetter', [], sdk.topGetter);
    },
  );

  test('nullable call and null-aware getter retain skipped arguments', () {
    for (final seed in <int?>[null, 0, 3]) {
      fixture.compare('nullable', [seed], () => sdk.nullable(seed));
    }
    for (final absent in [false, true]) {
      fixture.compare('nullAwareGetter', [
        absent,
      ], () => sdk.nullAwareGetter(absent));
      fixture.compare('nullAwareGenericGetter', [
        absent,
      ], () => sdk.nullAwareGenericGetter(absent));
    }
  });

  test('receiver and argument failures retain SDK order and finally', () {
    for (final value in <Object?>[null, 1, 'bad']) {
      fixture.compare('checkedReceiver', [
        value,
      ], () => sdk.checkedReceiver(value));
      fixture.compare('checkedArgument', [
        value,
      ], () => sdk.checkedArgument(value));
    }
    for (final valid in [false, true]) {
      fixture.compare('genericReceiverCheck', [
        valid,
      ], () => sdk.genericReceiverCheck(valid));
    }
    for (final stage in [0, 1, 3]) {
      fixture.compare('failure', [stage], () => sdk.failure(stage));
    }
    for (final stage in [0, 1, 2, 3]) {
      for (final form in [0, 1, 2, 3]) {
        fixture.compare('getterFailure', [
          stage,
          form,
        ], () => sdk.getterFailure(stage, form));
      }
    }
  });

  test('real members take precedence and dynamic never chooses extensions', () {
    fixture.compare('realMember', [], sdk.realMember);
    fixture.compare('dynamicMiss', [], sdk.dynamicMiss);
  });

  test('implicit extension call reuses flattened direct ABI', () {
    final direct = fixture.program.functions.singleWhere(
      (f) => f.target.name == 'direct',
    );
    final operations = direct.blocks.expand((b) => b.instructions);
    expect(
      operations.whereType<DirectCall>().where(
        (c) => c.target.name.endsWith(':method:call>'),
      ),
      hasLength(2),
    );
    expect(operations.whereType<InstanceCall>(), isEmpty);
    expect(operations.whereType<MakeClosure>(), isEmpty);
  });
}
