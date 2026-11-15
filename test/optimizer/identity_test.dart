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
    ('freshAndFresh', source.freshAndFresh()),
    ('factoryFresh', source.factoryFresh()),
    ('nestedFactory', source.nestedFactory()),
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
  test(
    'views of one unknown value retain identity without conflating inputs',
    () {
      for (final name in ['sameInput', 'sameViews']) {
        final function = body(name);
        final facts = optimize(function);
        expect(
          facts.returnedBy(function.target).constant?.structuralKey,
          const Constant.boolean(true).structuralKey,
        );
        final rewritten =
            facts.program.implementationOf(function.target) as IrFunction;
        expect(
          rewritten.blocks
              .expand((block) => block.instructions)
              .whereType<Identical>(),
          isEmpty,
        );
      }
      final distinct = body('unknownPair');
      final facts = optimize(distinct);
      expect(facts.returnedBy(distinct.target).constant, isNull);
      final rewritten =
          facts.program.implementationOf(distinct.target) as IrFunction;
      final object = Object();
      for (final args in [
        [object, object],
        [object, Object()],
        [null, null],
      ]) {
        expect(
          IrInterpreter(facts.program, {}).run(rewritten, args),
          source.unknownPair(args.first, args.last),
        );
      }
    },
  );
  test('borrowed and published return aliases keep the same identity', () {
    for (final (name, evaluate) in [
      ('borrowedIdentity', source.borrowedIdentity),
      ('publishedIdentity', source.publishedIdentity),
    ]) {
      final function = body(name);
      final facts = optimize(function);
      final rewritten =
          facts.program.implementationOf(function.target) as IrFunction;
      expect(evaluate(), isTrue);
      expect(IrInterpreter(program, {}).run(function, []), isTrue);
      expect(IrInterpreter(facts.program, {}).run(rewritten, []), isTrue);
    }
  });
  test(
    'possible aliases and repeated allocation generations stay conditional',
    () {
      for (final name in ['selectedFresh', 'repeatedFresh']) {
        final function = body(name);
        final facts = optimize(function);
        expect(facts.returnedBy(function.target).constant, isNull);
        final rewritten =
            facts.program.implementationOf(function.target) as IrFunction;
        for (final alias in [false, true]) {
          for (final count in name == 'repeatedFresh' ? [0, 1, 4] : [0]) {
            final arguments = [if (name == 'repeatedFresh') count, alias];
            final expected = name == 'repeatedFresh'
                ? source.repeatedFresh(count, alias)
                : source.selectedFresh(alias);
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
