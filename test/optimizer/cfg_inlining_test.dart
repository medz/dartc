import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/cfg_inlining.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/cfg_inlining.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  for (final (name, helper, invoke) in [
    ('branch', 'choose', source.branch),
    ('loop', 'sum', source.loop),
    ('exceptions', 'guarded', source.exceptions),
    ('neverCall', 'fail', source.neverCall),
  ]) {
    test('$name preserves behavior after control-flow inlining', () {
      final entry = program.functions.singleWhere((f) => f.target.name == name);
      final callee = program.functions.singleWhere(
        (f) => f.target.name == helper,
      );
      final before = ProgramFlow(
        program,
        [],
        openEntries: [entry.target],
      ).facts;
      final result = const DirectCallInlining(
        maxCalleeCost: 200,
        maxCallerGrowth: 2000,
      ).run(before);
      final body = result.implementationOf(entry.target) as IrFunction;
      expect(body.callees, isNot(contains(callee.target)));
      expect(
        body.sourceLocations.values.any(
          (origin) => origin.function == callee.target,
        ),
        isTrue,
      );
      for (final input in [-3, -2, -1, 0, 1, 3, 7]) {
        final expected = invoke(input);
        for (final graph in [program, result]) {
          final function = graph.implementationOf(entry.target) as IrFunction;
          expect(
            IrInterpreter(graph, {}).run(function, [input]),
            expected,
            reason: 'input=$input',
          );
        }
      }
      expect(() => before.checkProgram(result), throwsArgumentError);
    });
  }
  for (final (name, invoke) in [
    ('closureThroughCall', source.closureThroughCall),
    ('closureGeneric', source.closureGeneric),
    ('closureCells', source.closureCells),
  ]) {
    test('$name expands captures without retaining closure environments', () {
      final entry = program.functions.singleWhere((f) => f.target.name == name);
      final facts = ProgramOptimizer([
        const ProgramSimplification(),
        const ProgramCallSpecialization(),
        const ProgramStoragePromotion(),
        const ProgramStorageElimination(),
        name == 'closureCells'
            ? const DirectCallInlining(
                maxCalleeCost: 200,
                maxCallerGrowth: 2000,
              )
            : const DirectCallInlining(),
      ]).run(program, const [], openEntries: [entry.target]);
      final body = facts.program.implementationOf(entry.target) as IrFunction;
      expect(
        body.blocks
            .expand(
              (block) => [
                ...block.instructions,
                if (block.end case Invoke(:final operation)) operation,
              ],
            )
            .where(
              (operation) =>
                  operation is FunctionCall || operation is MakeClosure,
            ),
        isEmpty,
      );
      for (final input in [-3, -1, 0, 1, 9]) {
        expect(
          IrInterpreter(facts.program, {}).run(body, [input]),
          invoke(input),
        );
      }
    });
  }
}
