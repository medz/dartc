import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
import 'package:dartc/src/optimizer/program_optimizer.dart';
import 'package:dartc/src/optimizer/simplification.dart';
import 'package:dartc/src/optimizer/storage_elimination.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/object_state.dart' as source;

void main() {
  late IrProgram program;
  late IrFunction entry, invokeSaved, captured;
  late FunctionCall savedCall;
  late GlobalVariable saved;

  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/object_state.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
    entry = program.functions.singleWhere((f) => f.target.name == 'evaluate');
    invokeSaved = program.functions.singleWhere(
      (f) => f.target.name == 'invokeSaved',
    );
    captured = program.functions.singleWhere(
      (f) => f.target.kind == .closure && f.target.enclosing == entry.target,
    );
    saved = program.globals.singleWhere((global) => global.name == 'saved');
    savedCall = invokeSaved.blocks
        .expand(
          (block) => [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
        )
        .whereType<FunctionCall>()
        .single;
  });

  for (final first in [true, false]) {
    test(
      'follows concrete aliases, captures and replaced function values ($first)',
      () {
        final expected = first ? '7:2:7:4' : '1:7:7:6';
        expect(source.evaluate(first), expected);
        expect(IrInterpreter(program, {}).run(entry, [first]), expected);
        final facts = ProgramFlow(program, [
          (
            target: entry.target,
            arguments: [FlowValue.constant(Constant.boolean(first))],
          ),
        ]).facts;
        expect(
          facts.returnedBy(invokeSaved.target).constant?.structuralKey,
          Constant.integer(first ? 4 : 6).structuralKey,
        );
        expect(
          facts.returnedBy(captured.target).constant?.structuralKey,
          const Constant.integer(7).structuralKey,
        );
        expect(facts.targetsOf(savedCall).map((target) => target.name), [
          first ? 'increment' : 'twice',
        ]);
        expect(facts.hasUnknownCall(savedCall), isFalse);
        expect(facts.definitions, isNot(contains(saved.initializer)));
        final optimized = ProgramOptimizer(const [
          ProgramSimplification(),
          ProgramStorageElimination(),
        ]).run(program, facts.entries);
        final rewritten =
            optimized.program.implementationOf(entry.target) as IrFunction;
        expect(
          IrInterpreter(optimized.program, {}).run(rewritten, [first]),
          expected,
        );
        final residual = optimized.program.functions
            .where((body) => optimized.definitions.contains(body.target))
            .expand((body) => body.blocks)
            .expand(
              (block) => [
                ...block.instructions,
                if (block.end case Invoke(:final operation)) operation,
              ],
            )
            .toList();
        expect(
          residual.where(
            (op) => op is StoreGlobal || op is StoreField || op is WriteCell,
          ),
          isEmpty,
          reason: 'the remaining result no longer observes the source storage',
        );
        expect(
          residual.where(
            (op) => op is Construct || op is NewCell || op is MakeClosure,
          ),
          isEmpty,
          reason:
              'source object and closure shapes are not execution obligations',
        );
      },
    );
  }

  test('unknown input keeps both real targets without reviving the overwritten source', () {
    final facts = ProgramFlow(program, [
      (target: entry.target, arguments: [FlowValue.unknown(.boolean)]),
    ]).facts;
    expect(
      facts.targetsOf(savedCall).map((target) => target.name),
      unorderedEquals(['increment', 'twice']),
    );
    expect(facts.hasUnknownCall(savedCall), isFalse);
    expect(facts.definitions, isNot(contains(saved.initializer)));
    expect(facts.returnedBy(invokeSaved.target).constant, isNull);
  });
}
