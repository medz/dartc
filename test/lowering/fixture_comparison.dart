import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/effects.dart' as effects;

/// Compares a lowered fixture with the SDK, including failures and effect order.
final class FixtureComparison(final IrProgram program) {
  static Future<FixtureComparison> load(String fixture) async => .new(
    await AnalysisSession(['test/lowering/fixtures/$fixture.dart'])
        .use((input) => Lowering().lower(input).program),
  );

  static final _effects = Uri.base.resolve(
    'test/lowering/fixtures/effects.dart',
  );
  late final _runner = IrInterpreter(program, {
    (_effects, 'tick'): effects.tick,
    (_effects, 'probe'): effects.probe,
  });
  late final _functions = {
    for (final function in program.functions)
      if (function.target.owner == null) function.target.name: function,
  };

  void compare(String name, List<Object?> args, Object? Function() expected) {
    final function = _functions[name];
    expect(function, isNotNull, reason: 'Missing lowered fixture $name');
    final reference = _observe(expected);
    final actual = _observe(() => _runner.run(function!, args));
    final reason = '$name($args)';
    expect(actual.$1, reference.$1, reason: '$reason result');
    expect(actual.$2, reference.$2, reason: '$reason exception');
    expect(actual.$3, reference.$3, reason: '$reason effects');
  }

  static (Object?, Object?, List<int>) _observe(Object? Function() run) {
    effects.calls.clear();
    Object? result;
    Object? error;
    try {
      result = run();
    } catch (e) {
      error = switch (e) {
        StateError(:final message) => (StateError, message),
        AssertionError(:final message) => (AssertionError, message),
        TypeError() => TypeError,
        int() || String() || bool() => e,
        _ => e.runtimeType,
      };
    }
    return (result, error, List.of(effects.calls));
  }
}
