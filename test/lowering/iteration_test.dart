import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import 'fixture_runner.dart';
import 'fixtures/iteration.dart' as sdk;

void main() {
  late FixtureRunner runner;
  late Map<String, IrFunction> functions;
  setUpAll(() async {
    final program = await CheckedLibraries.read([
      'test/lowering/fixtures/iteration.dart',
    ], Lowering.lower);
    runner = FixtureRunner(program, {});
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
