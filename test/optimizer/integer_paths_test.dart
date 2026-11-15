import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/integer_paths.dart' as source;

void main() {
  late IrProgram program;
  IrFunction body(String name) =>
      program.functions.singleWhere((body) => body.target.name == name);
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/integer_paths.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  for (final (name, evaluate) in <(String, int Function(int))>[
    ('guardedShift', source.guardedShift),
    ('checkedShift', source.checkedShift),
    ('joinedBranches', source.joinedBranches),
    ('wrapping', source.wrapping),
    ('guardedAliases', source.guardedAliases),
    ('overwrittenAlias', source.overwrittenAlias),
  ]) {
    test('source integer paths preserve $name for runtime input', () {
      final function = body(name);
      final facts = ProgramOptimizer(const [ProgramSimplification()])
          .run(program, [
            (target: function.target, arguments: [FlowValue.unknown(.integer)]),
          ]);
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      for (final value in [
        FlowIntegerRange.minimum,
        -11,
        -1,
        0,
        1,
        3,
        4,
        11,
        63,
        64,
        FlowIntegerRange.maximum,
      ]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [value]),
          evaluate(value),
        );
      }
      final shifts = rewritten.blocks
          .expand(
            (block) => [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ],
          )
          .whereType<IntBinary>()
          .where((operation) => operation.operator == .shiftLeft);
      if (name == 'guardedShift' || name == 'guardedAliases') {
        expect(shifts, isEmpty);
      }
      if (name == 'checkedShift') expect(shifts, isNotEmpty);
    });
  }

  test('checked aliases constrain later reads of the same stored value', () {
    final function = body('guardedAliases');
    final facts = ProgramFlow(program, [
      (target: function.target, arguments: [FlowValue.unknown(.integer)]),
    ]).facts;
    final operations = function.blocks
        .expand(
          (block) => [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ],
        )
        .whereType<IntBinary>();
    final offset = operations.singleWhere(
      (operation) => operation.operator == .multiply,
    );
    expect(facts.valueOf(offset).integers, FlowIntegerRange(0, 24));
    final shift = operations.singleWhere(
      (operation) => operation.operator == .shiftLeft,
    );
    expect(facts.exitsOf(shift), (normal: true, exceptional: false));
  });

  test(
    'bounded source loops carry branch ranges through parameterless edges',
    () {
      final function = body('boundedLoop');
      final facts = ProgramFlow(program, [
        (target: function.target, arguments: []),
      ]).facts;
      expect(
        facts.returnedBy(function.target).constant?.structuralKey,
        Constant.integer(source.boundedLoop()).structuralKey,
      );
      final operations = function.blocks
          .expand(
            (block) => [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ],
          )
          .whereType<IntBinary>();
      final shift = operations.singleWhere(
        (operation) => operation.operator == .shiftLeft,
      );
      expect(facts.exitsOf(shift), (normal: true, exceptional: false));
      final offset = operations.singleWhere(
        (operation) => operation.operator == .multiply,
      );
      expect(facts.valueOf(offset).integers, FlowIntegerRange(0, 24));
    },
  );

  test(
    'unsigned shift ranges include the signed transition at a zero count',
    () {
      final function = body('unsignedShift');
      for (final (low, high) in [
        (-8, -4),
        (-8, 0),
        (-8, 8),
        (FlowIntegerRange.minimum, -1),
        (0, FlowIntegerRange.maximum),
        (FlowIntegerRange.minimum, FlowIntegerRange.maximum),
      ]) {
        for (final (begin, end) in [
          (0, 1),
          (0, 2),
          (0, 64),
          (1, 63),
          (63, FlowIntegerRange.maximum),
          (0, FlowIntegerRange.maximum),
        ]) {
          final facts = ProgramFlow(program, [
            (
              target: function.target,
              arguments: [
                FlowValue.integerRange(FlowIntegerRange(low, high)),
                FlowValue.integerRange(FlowIntegerRange(begin, end)),
              ],
            ),
          ]).facts;
          final range = facts.returnedBy(function.target).integers!;
          for (final value in {
            low,
            high,
            if (low <= -1 && high >= -1) -1,
            if (low <= 0 && high >= 0) 0,
          }) {
            for (final count in {
              begin,
              end,
              if (begin <= 1 && end >= 1) 1,
              if (begin <= 63 && end >= 63) 63,
            }) {
              expect(
                range.contains(source.unsignedShift(value, count)),
                isTrue,
                reason: '$low..$high >>> $begin..$end lost $value >>> $count',
              );
            }
          }
        }
      }
    },
  );
}
