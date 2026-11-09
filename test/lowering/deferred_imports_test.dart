import 'package:dartc/ir.dart';
import 'package:dartc/analyzer.dart';
import 'package:dartc/lowering.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/deferred_imports.dart' as sdk;
import 'fixtures/effects.dart' as effects;

void main() {
  test(
    'analyzer-resolved unnamed tear-offs retain their deferred check',
    () async {
      final program = await AnalysisSession([
        'test/lowering/fixtures/deferred_unnamed_tearoff.dart',
        'test/lowering/fixtures/deferred_library.dart',
      ]).use((input) => Lowering().lower(input).program);
      final runner = IrInterpreter(program, {});
      final create = program.functions.singleWhere(
        (f) => f.target.name == 'create',
      );
      expect(await runner.resolveAsync(runner.run(create, [])), 42);
    },
  );
  test(
    'deferred prefixes check before effects and load independently',
    () async {
      final program = await AnalysisSession([
        'test/lowering/fixtures/deferred_imports.dart',
        'test/lowering/fixtures/deferred_library.dart',
      ]).use((input) => Lowering().lower(input).program);
      final runner = IrInterpreter(program, {
        (Uri.base.resolve('test/lowering/fixtures/effects.dart'), 'tick'):
            effects.tick,
      });
      effects.calls.clear();
      final expected = await sdk.exercise();
      final calls = List.of(effects.calls);
      effects.calls.clear();
      final run = program.functions.singleWhere(
        (f) => f.target.name == 'exercise',
      );
      final actual = await runner.resolveAsync(runner.run(run, []));
      expect(actual, expected);
      expect(effects.calls, calls);
      expect(
        program.functions.expand((f) => f.deferredImports).toSet(),
        hasLength(2),
      );
      final operations = program.functions
          .expand((f) => f.blocks)
          .expand(
            (b) => [
              ...b.instructions,
              if (b.end case Invoke(:final operation)) operation,
            ],
          );
      expect(operations.whereType<LoadLibrary>(), hasLength(2));
      expect(operations.whereType<CheckLibraryLoaded>(), isNotEmpty);
    },
  );
}
