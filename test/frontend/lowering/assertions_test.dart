import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/assertions.dart' as sdk;
import 'fixtures/effects.dart' as effects;

void main() {
  late Map<String, IrFunction> enabled;
  late Map<String, IrFunction> disabled;
  late IrInterpreter enabledRunner;
  late IrInterpreter disabledRunner;
  setUpAll(() async {
    final programs =
        await AnalysisSession([
          'test/frontend/lowering/fixtures/assertions.dart',
        ]).use(
          (input) => (
            Lowering(enableAssertions: true).lower(input).program,
            Lowering().lower(input).program,
          ),
        );
    Map<String, IrFunction> functions(IrProgram program) => {
      for (final fn in program.functions)
        if (fn.target.owner == null && fn.target.enclosing == null)
          fn.target.name: fn,
    };
    enabled = functions(programs.$1);
    disabled = functions(programs.$2);
    final uri = Uri.base.resolve(
      'test/frontend/lowering/fixtures/effects.dart',
    );
    final imports = <(Uri, String), Object? Function(int)>{
      (uri, 'tick'): effects.tick,
      (uri, 'probe'): effects.probe,
    };
    enabledRunner = IrInterpreter(programs.$1, imports);
    disabledRunner = IrInterpreter(programs.$2, imports);
  });

  (Object?, Object?, List<int>) observe(Object? Function() run) {
    effects.calls.clear();
    try {
      return (run(), null, List.of(effects.calls));
    } catch (error) {
      final normalized = switch (error) {
        AssertionError(:final message) => (AssertionError, message),
        StateError(:final message) => (StateError, message),
        _ => error,
      };
      return (null, normalized, List.of(effects.calls));
    }
  }

  void checkObservation(
    (Object?, Object?, List<int>) actual,
    (Object?, Object?, List<int>) expected,
  ) {
    expect(actual.$1, expected.$1);
    expect(actual.$2, expected.$2);
    expect(actual.$3, expected.$3);
  }

  void compare(
    String name,
    List<Object?> arguments,
    Object? Function() native,
  ) {
    final expected = observe(native);
    checkObservation(
      observe(() => enabledRunner.run(enabled[name]!, arguments)),
      expected,
    );
  }

  test('disabled assertions omit nested closure bodies', () async {
    final program = await AnalysisSession([
      'test/frontend/lowering/fixtures/disabled_assertion_closure.dart',
    ]).use((input) => Lowering().lower(input).program);
    expect(
      program.functions.every((fn) => fn.target.enclosing == null),
      isTrue,
    );
    final runner = IrInterpreter(program, {});
    for (final (name, expected) in [
      ('skippedClosure', 5),
      ('skippedConstructor', 6),
      ('skippedExtension', 3),
    ]) {
      final fn = program.functions.singleWhere((fn) => fn.target.name == name);
      expect(runner.run(fn, []), expected);
    }
    final checked = await AnalysisSession([
      'test/frontend/lowering/fixtures/disabled_assertion_closure.dart',
    ]).use((input) => Lowering(enableAssertions: true).lower(input).program);
    expect(checked.functions.any((fn) => fn.target.enclosing != null), isTrue);
  });

  test('enabled assertions match condition and lazy message evaluation', () {
    for (final input in [-1, 0, 1]) {
      compare('asserted', [input], () => sdk.asserted(input));
      compare('closureCondition', [input], () => sdk.closureCondition(input));
    }
    for (final condition in [true, false]) {
      compare('withoutMessage', [
        condition,
      ], () => sdk.withoutMessage(condition));
      compare('throwingMessage', [
        condition,
      ], () => sdk.throwingMessage(condition));
    }
  });

  test('assertion errors and throwing conditions obey catch and finally', () {
    for (final input in [-1, 0, 1]) {
      compare('caught', [input], () => sdk.caught(input));
      compare('typedCatch', [input], () => sdk.typedCatch(input));
    }
    for (final condition in [true, false]) {
      compare('finalizerOverride', [
        condition,
      ], () => sdk.finalizerOverride(condition));
    }
  });

  test('constructor assertions retain initializer and body order', () {
    for (final input in [-1, 0, 1]) {
      compare('construct', [input], () => sdk.construct(input));
      compare('constructEarly', [input], () => sdk.constructEarly(input));
    }
  });

  test(
    'default-disabled assertions evaluate neither condition nor message',
    () {
      for (final input in [-1, 0, 1]) {
        checkObservation(
          observe(() => disabledRunner.run(disabled['asserted']!, [input])),
          (30, null, [30]),
        );
        checkObservation(
          observe(
            () => disabledRunner.run(disabled['closureCondition']!, [input]),
          ),
          (82, null, [82]),
        );
        checkObservation(
          observe(() => disabledRunner.run(disabled['construct']!, [input])),
          (90, null, [90, 92]),
        );
        checkObservation(
          observe(
            () => disabledRunner.run(disabled['constructEarly']!, [input]),
          ),
          (101, null, [101]),
        );
      }
      checkObservation(
        observe(
          () => disabledRunner.run(disabled['throwingMessage']!, [false]),
        ),
        (50, null, [50]),
      );
      checkObservation(
        observe(() => disabledRunner.run(disabled['caught']!, [0])),
        (61, null, [61, 63]),
      );
    },
  );
}
