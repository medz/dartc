import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/read_dependencies.dart' as source;

void main() {
  late IrProgram program;
  IrFunction body(String name) => program.functions.singleWhere(
    (body) => body.target.name == name && body.target.owner == null,
  );
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/read_dependencies.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  for (final (name, evaluate, constant) in <(String, int Function(int), bool)>[
    ('unrelatedField', source.unrelatedField, true),
    ('unrelatedGlobal', source.unrelatedGlobal, true),
    ('captured', source.captured, true),
    ('changedField', source.changedField, false),
    ('changedGlobal', source.changedGlobal, false),
  ]) {
    test('source $name observes only its actual inputs', () {
      final function = body(name);
      final entry = (
        target: function.target,
        arguments: [FlowValue.unknown(.integer)],
      );
      final facts = ProgramFlow(program, [entry]).facts;
      if (constant) {
        final readers = switch (name) {
          'unrelatedField' => [body('readValue')],
          'unrelatedGlobal' => [body('forwardGlobal'), body('readGlobal')],
          _ => [body('read')],
        };
        for (final reader in readers) {
          expect(facts.activationsOf(reader.target), hasLength(1));
        }
      }
      final optimized = ProgramOptimizer(const [
        ProgramSimplification(),
        ProgramCallSpecialization(),
        ProgramStoragePromotion(),
        ProgramStorageElimination(),
        DirectCallInlining(),
      ]).run(program, [entry]);
      final rewritten =
          optimized.program.implementationOf(function.target) as IrFunction;
      for (final value in [
        FlowIntegerRange.minimum,
        -8,
        0,
        9,
        FlowIntegerRange.maximum,
      ]) {
        expect(
          IrInterpreter(program, {}).run(function, [value]),
          evaluate(value),
        );
        expect(
          IrInterpreter(optimized.program, {}).run(rewritten, [value]),
          evaluate(value),
        );
      }
      if (constant) {
        expect(
          optimized.returnedBy(function.target).constant?.structuralKey,
          const Constant.integer(14).structuralKey,
        );
        expect(rewritten.blocks, hasLength(1));
        expect(rewritten.entry.instructions, isEmpty);
      }
    });
  }

  test(
    'virtual readers and lazy initialization retain their observable writes',
    () {
      for (final name in ['virtualRead', 'lazyRead']) {
        final function = body(name);
        final facts =
            ProgramOptimizer(const [
              ProgramSimplification(),
              ProgramCallSpecialization(),
              ProgramStoragePromotion(),
              ProgramStorageElimination(),
              DirectCallInlining(),
            ]).run(program, [
              (
                target: function.target,
                arguments: function.target.parameterTypes
                    .map(FlowValue.unknown)
                    .toList(),
              ),
            ]);
        final rewritten =
            facts.program.implementationOf(function.target) as IrFunction;
        for (final value in [-8, 0, 9]) {
          for (final writes
              in name == 'virtualRead' ? [false, true] : [false]) {
            final arguments = [if (name == 'virtualRead') writes, value];
            final expected = name == 'virtualRead'
                ? source.virtualRead(writes, value)
                : source.lazyRead(value);
            expect(
              IrInterpreter(program, {}).run(function, arguments),
              expected,
            );
            expect(
              IrInterpreter(facts.program, {}).run(rewritten, arguments),
              expected,
            );
          }
        }
      }
    },
  );
}
