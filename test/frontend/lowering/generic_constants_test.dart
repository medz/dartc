import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/generic_constants.dart' as sdk;

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await AnalysisSession([
      'test/frontend/lowering/fixtures/generic_constants.dart',
    ]).use((input) => Lowering().lower(input).program);
    runner = IrInterpreter(program, {});
    functions = {for (final fn in program.functions) fn.target.name: fn};
  });
  Object? run(String name, [List<Object?> arguments = const []]) =>
      runner.run(functions[name]!, arguments);
  test('constant and default function instantiation preserves arguments', () {
    for (final value in [-1, 0, 5]) {
      expect(
        run('genericConstantCalls', [value]),
        sdk.genericConstantCalls(value),
      );
      expect(
        run('genericConstantConstructors', [value]),
        sdk.genericConstantConstructors(value),
      );
    }
    for (final value in <Object>[1, 'one', true]) {
      expect(
        run('genericConstantChecks', [value]),
        sdk.genericConstantChecks(value),
      );
    }
    expect(run('genericConstantIdentity'), sdk.genericConstantIdentity());
  });
  test(
    'pattern comparison caching distinguishes function and owner arguments',
    () {
      for (final chooseInt in [false, true]) {
        expect(
          run('genericConstantPattern', [chooseInt]),
          sdk.genericConstantPattern(chooseInt),
        );
        expect(
          run('genericConstructorPattern', [chooseInt]),
          sdk.genericConstructorPattern(chooseInt),
        );
      }
    },
  );
  test(
    'constant constructor aliases preserve bound mapping and nominal identity',
    () {
      for (final value in [-1, 0, 3]) {
        expect(
          run('genericAliasConstants', [value]),
          sdk.genericAliasConstants(value),
        );
      }
      expect(
        run('genericAliasConstantIdentity'),
        sdk.genericAliasConstantIdentity(),
      );
      for (final first in [false, true]) {
        expect(
          run('genericAliasConstantPattern', [first]),
          sdk.genericAliasConstantPattern(first),
        );
        expect(
          run('genericInlineAliasPattern', [first]),
          sdk.genericInlineAliasPattern(first),
        );
      }
    },
  );
}
