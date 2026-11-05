import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/extension_access.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  setUpAll(() async {
    fixture = await FixtureComparison.load('extension_access');
  });
  for (final (name, function) in <(String, Object? Function(int))>[
    ('getterSetter', sdk.getterSetter),
    ('updates', sdk.updates),
    ('explicitIndex', sdk.explicitIndex),
    ('getterCall', sdk.getterCall),
    ('operatorUpdates', sdk.operatorUpdates),
    ('explicitOperators', sdk.explicitOperators),
    ('patterns', sdk.patterns),
    ('lexicalAccess', sdk.lexicalAccess),
    ('setterOnly', sdk.setterOnly),
    ('patternReuse', sdk.patternReuse),
    ('implicitSetterStatement', sdk.implicitSetterStatement),
    ('repeatedOperator', sdk.repeatedOperator),
    ('implicitGenericOperators', sdk.implicitGenericOperators),
  ]) {
    test('$name matches SDK values and effects', () {
      for (final seed in [-1, 0, 3]) {
        fixture.compare(name, [seed], () => function(seed));
      }
    });
  }
  test('null-aware and if-null access preserves skipped effects', () {
    for (final absent in [false, true]) {
      for (final empty in [false, true]) {
        fixture.compare('nullableAssignments', [
          absent,
          empty,
        ], () => sdk.nullableAssignments(absent, empty));
      }
      fixture.compare('ifNullIndex', [absent], () => sdk.ifNullIndex(absent));
    }
    for (final seed in <int?>[null, 0, 3]) {
      fixture.compare('nullableGetter', [seed], () => sdk.nullableGetter(seed));
      fixture.compare('nullablePattern', [
        seed,
      ], () => sdk.nullablePattern(seed));
    }
  });
  test('extension checks and failures preserve SDK evaluation order', () {
    for (final valid in [false, true]) {
      fixture.compare('receiverCheck', [valid], () => sdk.receiverCheck(valid));
      fixture.compare('operatorReceiverCheck', [
        valid,
      ], () => sdk.operatorReceiverCheck(valid));
    }
    for (final input in <Object?>[null, 0, 'bad']) {
      fixture.compare('indexCheck', [input], () => sdk.indexCheck(input));
      fixture.compare('explicitIndexCheck', [
        input,
      ], () => sdk.explicitIndexCheck(input));
      fixture.compare('explicitDynamic', [
        input,
      ], () => sdk.explicitDynamic(input));
    }
    for (final stage in [0, 1, 2, 3, 5]) {
      fixture.compare('exceptionalUpdate', [
        stage,
      ], () => sdk.exceptionalUpdate(stage));
    }
  });
  test(
    'assignment values use source order, separately from SDK reordering',
    () {
      effects.calls.clear();
      final uri = Uri.base.resolve('test/lowering/fixtures/effects.dart');
      final runner = FixtureRunner(fixture.program, {
        (uri, 'tick'): effects.tick,
      });
      for (final (name, order) in [
        ('implicitSetterValue', [1, 3, 5]),
        ('explicitIndexValue', [1, 6, 3, 5]),
      ]) {
        effects.calls.clear();
        final function = fixture.program.functions.singleWhere(
          (f) => f.target.name == name,
        );
        expect(runner.run(function, [3]), 4);
        expect(effects.calls, order, reason: name);
      }
      // The pinned SDK observation is evidence, not a required future behavior.
    },
  );
  test(
    'assignment source-order failures retain finally and skipped effects',
    () {
      final uri = Uri.base.resolve('test/lowering/fixtures/effects.dart');
      final runner = FixtureRunner(fixture.program, {
        (uri, 'tick'): effects.tick,
      });
      for (final (name, stage, order) in [
        ('explicitIndexFailure', 0, [1, 2, 3, 5, 8]),
        ('explicitIndexFailure', 1, [-1, 8]),
        ('explicitIndexFailure', 2, [1, -2, 8]),
        ('explicitIndexFailure', 3, [1, 2, -3, 8]),
        ('explicitIndexFailure', 4, [1, 2, 8]),
        ('explicitIndexFailure', 5, [1, 2, 3, 8]),
        ('implicitSetterFailure', 0, [1, 3, 5, 8]),
        ('implicitSetterFailure', 1, [-1, 8]),
        ('implicitSetterFailure', 3, [1, -3, 8]),
        ('implicitSetterFailure', 5, [1, 3, 8]),
      ]) {
        effects.calls.clear();
        final function = fixture.program.functions.singleWhere(
          (f) => f.target.name == name,
        );
        if (stage == 0) {
          expect(runner.run(function, [stage]), 7);
        } else {
          expect(
            () => runner.run(function, [stage]),
            stage >= 4 ? throwsA(isA<TypeError>()) : throwsA(isA<StateError>()),
          );
        }
        expect(effects.calls, order, reason: '$name($stage)');
      }
    },
  );
  test('pattern caches distinguish applied extension selection', () {
    fixture.compare('patternSelection', [], sdk.patternSelection);
  });
  test('extension operations use only flattened direct calls', () {
    final operations = fixture.program.functions
        .expand((f) => f.blocks)
        .expand((b) => b.instructions);
    expect(
      operations.whereType<DirectCall>().any(
        (c) => c.target.name.startsWith('<extension:'),
      ),
      isTrue,
    );
    expect(
      operations.whereType<InstanceCall>().where(
        (c) => c.member.name.startsWith('<extension:'),
      ),
      isEmpty,
    );
    expect(
      operations.whereType<BindMethod>().where(
        (c) => c.method.name.startsWith('<extension:'),
      ),
      isEmpty,
    );
  });
}
