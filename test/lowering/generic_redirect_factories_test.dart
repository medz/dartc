import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/generic_redirect_factory.dart' as sdk;

void main() {
  late FixtureRunner runner;
  late IrProgram program;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await CheckedLibraries.read([
      'test/lowering/fixtures/generic_redirect_factory.dart',
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
    expect(actual.$2, reference.$2, reason: name);
    expect(actual.$1, reference.$1, reason: name);
    expect(actual.$3, reference.$3, reason: name);
  }

  test(
    'generic redirect chains preserve types, defaults and evaluation order',
    () {
      for (final seed in [-1, 0, 4]) {
        for (var mode = 0; mode < 6; mode++) {
          compare('genericRedirect', [
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
        compare('genericRedirectTearoff', [
          seed,
          mode,
        ], () => sdk.genericRedirectTearoff(seed, mode));
      }
      compare('genericRedirectBounds', [
        seed,
      ], () => sdk.genericRedirectBounds(seed));
      compare('genericRedirectEnvironment', [
        seed,
      ], () => sdk.genericRedirectEnvironment(seed));
    }
  });

  test('redirect tearoffs retain source and applied owner identity', () {
    compare('genericRedirectIdentity', [], sdk.genericRedirectIdentity);
  });

  test('redirect resolution validates destination and source bounds', () {
    final source = program.classes.singleWhere(
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
