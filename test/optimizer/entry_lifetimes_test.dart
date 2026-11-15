import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/entry_lifetimes.dart' as source;

void main() {
  late IrProgram program;
  IrFunction body(String name) =>
      program.functions.singleWhere((function) => function.target.name == name);
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/entry_lifetimes.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  test('open entries do not inherit private objects from previous calls', () {
    final function = body('privateCounter');
    final facts = ProgramFlow(
      program,
      [],
      openEntries: [function.target],
    ).facts;
    final allocation = function.blocks
        .expand((block) => block.instructions)
        .whereType<Construct>()
        .single;
    final before = facts.pointStateOf(allocation)!.before;
    for (final object in facts.valueOf(allocation).objects) {
      expect(before.containsObject(object), isFalse);
    }
    final optimized = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      DirectCallInlining(),
    ]).run(program, [], openEntries: [function.target]);
    final rewritten =
        optimized.program.implementationOf(function.target) as IrFunction;
    final interpreter = IrInterpreter(optimized.program, {});
    for (final value in [-7, 0, 1, 41, FlowIntegerRange.maximum]) {
      expect(interpreter.run(rewritten, [value]), source.privateCounter(value));
    }
  });

  test(
    'public global changes and returned closure state survive entry calls',
    () {
      final increment = body('incrementGlobal'), read = body('readGlobal');
      final factory = body('retainedCounter');
      final facts = ProgramOptimizer(const [ProgramSimplification()]).run(
        program,
        [],
        openEntries: [increment.target, read.target, factory.target],
      );
      expect(facts.returnedBy(read.target).constant, isNull);
      final interpreter = IrInterpreter(facts.program, {});
      IrFunction rewritten(IrFunction function) =>
          facts.program.implementationOf(function.target) as IrFunction;
      expect(interpreter.run(rewritten(read), []), 0);
      expect(interpreter.run(rewritten(increment), []), 1);
      expect(interpreter.run(rewritten(increment), []), 2);
      expect(interpreter.run(rewritten(read), []), 2);
      final first = interpreter.run(rewritten(factory), [7]);
      final second = interpreter.run(rewritten(factory), [20]);
      expect(interpreter.call(first, []), 8);
      expect(interpreter.call(second, []), 21);
      expect(interpreter.call(first, []), 9);
    },
  );

  test('every invocation assigns its local before a do-while exit', () {
    final function = body('deferredDouble');
    final facts = ProgramFlow(
      program,
      [],
      openEntries: [function.target],
    ).facts;
    final reads = function.blocks
        .expand(
          (block) => [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
        )
        .whereType<ReadCell>();
    expect(reads, isNotEmpty);
    for (final read in reads) {
      expect(facts.exitsOf(read).exceptional, isFalse);
    }
    final optimized = ProgramOptimizer(const [
      ProgramSimplification(),
      ProgramCallSpecialization(),
      ProgramStoragePromotion(),
      ProgramStorageElimination(),
      DirectCallInlining(),
    ]).run(program, [], openEntries: [function.target]);
    final rewritten =
        optimized.program.implementationOf(function.target) as IrFunction;
    for (final value in [-3.5, -0.0, 2.5]) {
      for (final count in [-3, 0, 1, 4, 9]) {
        expect(
          IrInterpreter(optimized.program, {}).run(rewritten, [value, count]),
          source.deferredDouble(value, count),
        );
      }
    }
  });
}
