import 'package:dartc/ir.dart';
import 'package:dartc/frontend.dart';
import 'package:test/test.dart';

import '../../support/ir_interpreter.dart';
import 'fixtures/iteration.dart' as sdk;

void main() {
  late IrInterpreter runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await AnalysisSession([
      'test/frontend/lowering/fixtures/iteration.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    runner = IrInterpreter(program, {});
    functions = {
      for (final f in program.functions)
        if (f.target.enclosing == null) f.target.name: f,
    };
  });

  test(
    'statement and collection headers share const and deferred initialization',
    () {
      expect(
        runner.run(functions['constantHeaders']!, []),
        sdk.constantHeaders(),
      );
      expect(
        runner.run(functions['deferredHeaders']!, []),
        sdk.deferredHeaders(),
      );
      expect(
        runner.run(functions['expressionAndPatternHeaders']!, []),
        sdk.expressionAndPatternHeaders(),
      );
    },
  );

  test(
    'preserves uninitialized final headers and abrupt header evaluation',
    () {
      expect(
        runner.run(functions['nullableFinalHeaders']!, []),
        sdk.nullableFinalHeaders(),
      );
      for (final failure in [0, 1, 2, 3]) {
        expect(
          runner.run(functions['abruptHeaders']!, [failure]),
          sdk.abruptHeaders(failure),
        );
      }
    },
  );

  test('copies captured cells before updates and after continue/finally', () {
    for (final limit in [0, 1, 2, 5]) {
      expect(
        runner.run(functions['updateCaptures']!, [limit]),
        sdk.updateCaptures(limit),
        reason: 'limit $limit',
      );
    }
  });
}
