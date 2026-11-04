import 'package:dartc/ir.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/effects.dart' as effects;
import 'fixtures/generic_semantics.dart' as sdk;

void main() {
  late FixtureRunner runner;
  late IrProgram program;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    program = await CheckedLibraries.read([
      'test/lowering/fixtures/generic_semantics.dart',
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
      ]) {
        compare(name, [seed], () => function(seed));
      }
      for (final valid in [false, true]) {
        compare('genericInterfaceCast', [
          seed,
          valid,
        ], () => sdk.genericInterfaceCast(seed, valid));
      }
    }
  });
}
