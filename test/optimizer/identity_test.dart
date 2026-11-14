import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/identity.dart' as source;

void main() {
  late IrProgram program;
  IrFunction body(String name) =>
      program.functions.singleWhere((body) => body.target.name == name);
  ProgramFlowFacts optimize(IrFunction function) =>
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
  setUpAll(() async {
    program = await AnalysisSession(['test/optimizer/fixtures/identity.dart'])
        .use((input) async => (await Lowering().lower(input)).program);
  });
  for (final (name, expected) in [
    ('constantAndFresh', source.constantAndFresh()),
    ('freshAndConstant', source.freshAndConstant()),
    ('sameConstant', source.sameConstant()),
    ('differentConstants', source.differentConstants()),
  ]) {
    test(
      'source $name has its determined identity without residual comparison',
      () {
        final function = body(name);
        final facts = optimize(function);
        expect(
          facts.returnedBy(function.target).constant?.structuralKey,
          Constant.boolean(expected).structuralKey,
        );
        final rewritten =
            facts.program.implementationOf(function.target) as IrFunction;
        expect(
          rewritten.blocks
              .expand((block) => block.instructions)
              .whereType<Identical>(),
          isEmpty,
        );
        expect(IrInterpreter(facts.program, {}).run(rewritten, []), expected);
      },
    );
  }
  test(
    'identity stays conditional when an alternative can be the constant',
    () {
      final function = body('selectedIdentity');
      final facts = optimize(function);
      expect(facts.returnedBy(function.target).constant, isNull);
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      for (final selected in [false, true]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, [selected]),
          source.selectedIdentity(selected),
        );
      }
      final unknown = body('unknownIdentity');
      expect(optimize(unknown).returnedBy(unknown.target).constant, isNull);
    },
  );
}
