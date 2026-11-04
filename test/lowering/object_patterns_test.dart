import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/object_patterns.dart' as sdk;

void main() {
  late FixtureRunner runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await CheckedLibraries.read([
      'test/lowering/fixtures/object_patterns.dart',
    ], Lowering.lower);
    functions = {
      for (final function in program.functions)
        if (function.target.owner == null) function.target.name: function,
    };
    final library = Uri.base.resolve('test/lowering/fixtures/effects.dart');
    runner = FixtureRunner(program, {
      (library, 'tick'): effects.tick,
      (library, 'probe'): effects.probe,
    });
  });

  void compare(String name, List<Object?> args, Object? Function() expected) {
    (Object?, Object?, List<int>) observe(Object? Function() run) {
      effects.calls.clear();
      Object? result;
      Object? error;
      try {
        result = run();
      } catch (e) {
        error = switch (e) {
          StateError(:final message) => (StateError, message),
          TypeError() => TypeError,
          _ => e.runtimeType,
        };
      }
      return (result, error, List.of(effects.calls));
    }

    final reference = observe(expected);
    final actual = observe(() => runner.run(functions[name]!, args));
    expect(actual.$1, reference.$1, reason: name);
    expect(actual.$2, reference.$2, reason: name);
    expect(actual.$3, reference.$3, reason: name);
  }

  test(
    'object fields preserve source order, dispatch, guards and exceptions',
    () {
      for (final seed in [-12, -1, 0, 1, 4]) {
        for (final derived in [false, true]) {
          compare('orderedObject', [
            seed,
            derived,
          ], () => sdk.orderedObject(seed, derived));
          compare('typeAlternativeObject', [
            seed,
            derived,
          ], () => sdk.typeAlternativeObject(seed, derived));
        }
        for (final (name, function) in <(String, int Function(int))>[
          ('shortObject', sdk.shortObject),
          ('wildcardObject', sdk.wildcardObject),
          ('nullableObject', sdk.nullableObject),
          ('assertObject', sdk.assertObject),
          ('declareObject', sdk.declareObject),
          ('assignObject', sdk.assignObject),
          ('methodObject', sdk.methodObject),
          ('nestedObject', sdk.nestedObject),
          ('alternativeObject', sdk.alternativeObject),
          ('andObject', sdk.andObject),
          ('nestedAlternativeObject', sdk.nestedAlternativeObject),
          ('switchObject', sdk.switchObject),
          ('switchStatementObject', sdk.switchStatementObject),
          ('castObject', sdk.castObject),
          ('nestedGetterObject', sdk.nestedGetterObject),
          ('loopObject', sdk.loopObject),
          ('guardedMutationObject', sdk.guardedMutationObject),
          ('narrowedGetterObject', sdk.narrowedGetterObject),
          ('separateMatchesObject', sdk.separateMatchesObject),
          ('relationalAndObject', sdk.relationalAndObject),
          ('relationalOrObject', sdk.relationalOrObject),
          ('equalityComplementObject', sdk.equalityComplementObject),
          ('distinctRelationalObject', sdk.distinctRelationalObject),
          ('guardedRelationalObject', sdk.guardedRelationalObject),
          ('canonicalRelationalObject', sdk.canonicalRelationalObject),
          ('relationalStatementObject', sdk.relationalStatementObject),
          ('recordEqualityObject', sdk.recordEqualityObject),
          ('distinctEqualityObject', sdk.distinctEqualityObject),
          ('nanEqualityObject', sdk.nanEqualityObject),
          ('receiverPathsObject', sdk.receiverPathsObject),
        ]) {
          compare(name, [seed], () => function(seed));
        }
      }
    },
  );

  test(
    'type misses do not access getters and builtin empty patterns match',
    () {
      for (final value in <Object?>[null, 42, 'hello', true, 1.5]) {
        compare('mismatchObject', [value], () => sdk.mismatchObject(value));
      }
    },
  );
}
