import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/scoped_state.dart' as source;

void main() {
  late IrProgram program;
  IrFunction body(String name) =>
      program.functions.singleWhere((body) => body.target.name == name);
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/scoped_state.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });
  for (final (entry, evaluate) in [
    ('restoreResult', source.restoreResult),
    ('observeResult', source.observeResult),
    ('incompleteResult', source.incompleteResult),
    ('overwrittenResult', source.overwrittenResult),
  ]) {
    test('$entry preserves observation and exception restoration', () {
      final function = body(entry);
      final facts =
          ProgramOptimizer(const [
            ProgramSimplification(),
            ProgramCallSpecialization(),
            ProgramStoragePromotion(),
            ProgramStorageElimination(),
            ProgramBranchSpecialization(),
            ProgramLoopSpecialization(),
            DirectCallInlining(),
          ]).run(program, [
            (target: function.target, arguments: [FlowValue.unknown(.integer)]),
          ]);
      final after = facts.program;
      if (entry == 'restoreResult') {
        expect(facts.definitions, {function.target});
        expect([
          for (final block
              in (after.implementationOf(function.target) as IrFunction).blocks)
            for (final operation in [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ])
              ...operation.effects,
        ], isEmpty);
      }
      for (final value in [-9, 0, 4]) {
        final expected = evaluate(value);
        for (final graph in [program, after]) {
          expect(
            IrInterpreter(graph, {}).run(
              graph.implementationOf(function.target) as IrFunction,
              [value],
            ),
            expected,
          );
        }
      }
    });
  }
}
