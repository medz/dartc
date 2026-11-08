import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_comparison.dart';
import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/extension_types_constructors.dart' as sdk;

void main() {
  late FixtureComparison fixture;
  late IrProgram disabled;
  setUpAll(() async {
    final programs =
        await AnalysisSession([
          'test/lowering/fixtures/extension_types_constructors.dart',
        ]).use(
          (input) => (
            Lowering(enableAssertions: true).lower(input).program,
            Lowering().lower(input).program,
          ),
        );
    fixture = FixtureComparison(programs.$1);
    disabled = programs.$2;
  });
  test('representation constructors preserve body effects and defaults', () {
    for (final x in [0, 1, 2, -1, -2, -3]) {
      for (final (name, call) in <(String, Object? Function(int))>[
        ('primary', sdk.primary),
        ('other', sdk.other),
        ('redirect', sdk.redirect),
        ('factory', sdk.factory),
        ('generic', sdk.generic),
        ('genericPrimary', sdk.genericPrimary),
        ('ordered', sdk.ordered),
        ('nullable', sdk.nullable),
        ('genericConstructor', sdk.genericConstructor),
        ('runtimeConst', sdk.runtimeConst),
        ('tearoff', sdk.tearoff),
        ('factoryTearoff', sdk.factoryTearoff),
      ]) {
        fixture.compare(name, [x], () => call(x));
      }
    }
    fixture.compare('constConstructors', [], sdk.constConstructors);
    fixture.compare('recursiveDefaults', [], sdk.recursiveDefaults);
    fixture.compare('staticDefaults', [], sdk.staticDefaults);
    for (final x in <Object?>[null, 3, 'bad']) {
      fixture.compare('nullableDynamic', [x], () => sdk.nullableDynamic(x));
    }
  });
  test(
    'disabled constructor assertions omit effects and closure bodies',
    () async {
      final uri = Uri.base.resolve('test/lowering/fixtures/effects.dart');
      final runner = FixtureRunner(disabled, {
        (uri, 'tick'): effects.tick,
        (uri, 'probe'): effects.probe,
      });
      effects.calls.clear();
      expect(
        runner.run(
          disabled.functions.singleWhere((f) => f.target.name == 'ordered'),
          [0],
        ),
        2,
      );
      expect(effects.calls, [2, 4, 5]);
    },
  );
  test('erased constructors use ordinary static functions and no storage', () {
    expect(disabled.classes, isEmpty);
    final constructors = disabled.functions.where(
      (f) => f.target.name.contains(':constructor:'),
    );
    expect(constructors, isNotEmpty);
    for (final f in constructors) {
      expect(f.target.kind, FunctionKind.function);
      expect(f.target.owner, isNull);
    }
  });
}
