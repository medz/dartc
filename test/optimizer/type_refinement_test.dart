import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/type_refinement.dart' as source;

void main() {
  final uri = Uri.parse('memory:type-refinement');
  late IrProgram sourceProgram;
  setUpAll(() async {
    sourceProgram = await AnalysisSession([
      'test/optimizer/fixtures/type_refinement.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  for (final example in <String, int Function(bool)>{
    'nullableGuard': source.nullableGuard,
    'nullAssertion': source.nullAssertion,
    'genericChecks': source.genericChecks,
  }.entries) {
    test('source guards preserve ${example.key}', () {
      final body = sourceProgram.functions.singleWhere(
        (body) => body.target.name == example.key,
      );
      final facts =
          ProgramOptimizer(const [
            ProgramCallSpecialization(),
            ProgramSimplification(),
          ]).run(sourceProgram, [
            (target: body.target, arguments: [FlowValue.unknown(.boolean)]),
          ]);
      final optimized =
          facts.program.implementationOf(body.target) as IrFunction;
      for (final selected in [true, false]) {
        final expected = example.value(selected);
        expect(
          IrInterpreter(facts.program, {}).run(optimized, [selected]),
          expected,
        );
        final exact = ProgramFlow(sourceProgram, [
          (
            target: body.target,
            arguments: [FlowValue.constant(Constant.boolean(selected))],
          ),
        ]).facts;
        expect(
          exact.returnedBy(body.target).constant?.structuralKey,
          Constant.integer(expected).structuralKey,
        );
      }
    });
  }

  for (final negated in [false, true]) {
    test('type-test edges filter both outcomes with negated=$negated', () {
      final target = FunctionTarget(uri, 'select', .object.nullable, [
        .object.nullable,
      ]);
      final entry = Block(target.parameterTypes);
      final test = entry.emit(
        TypeTest(
          entry.parameters.single,
          ValueType.integer.nullable,
          negated: negated,
        ),
      );
      final matches = test.refinement(!negated)!;
      final misses = test.refinement(negated)!;
      final yes = Block([matches.type])
        ..finish(const Return(Constant.nullValue()));
      final no = Block([misses.type]);
      no.finish(Return(no.parameters.single));
      final yesEdge = Jump(yes, [matches]), noEdge = Jump(no, [misses]);
      entry.finish(
        Branch(test, negated ? noEdge : yesEdge, negated ? yesEdge : noEdge),
      );
      final body = IrFunction(target, [entry, yes, no]);
      final program = IrProgram([], [body]);
      final values = FlowValue.constant(const Constant.integer(7))
          .join(FlowValue.constant(const Constant.string('other')))
          .join(FlowValue.constant(const Constant.nullValue()));
      final facts = ProgramFlow(program, [
        (target: target, arguments: [values]),
      ]).facts;
      expect(
        facts.valueOf(matches).constants.map((c) => c.structuralKey).toSet(),
        {
          const Constant.integer(7).structuralKey,
          const Constant.nullValue().structuralKey,
        },
      );
      expect(
        facts.valueOf(misses).constant?.structuralKey,
        const Constant.string('other').structuralKey,
      );
      expect(
        facts.valueOf(no.parameters.single),
        facts
            .valueOf(misses)
            .withSource(
              no.parameters.single,
              facts.activationsOf(target).single,
            ),
      );
      final exact = ProgramFlow(program, [
        (
          target: target,
          arguments: [FlowValue.constant(const Constant.integer(7))],
        ),
      ]).facts;
      expect(exact.valueOf(misses).isBottom, isTrue);
      expect(exact.equivalentsOf(misses), isEmpty);
      expect(exact.reachesBlock(no), isFalse);
    });
  }

  test(
    'null assertions refine normal values without losing exceptional paths',
    () {
      final target = FunctionTarget(uri, 'assertNotNull', .object, [
        .dynamicType,
      ]);
      final entry = Block(target.parameterTypes);
      final checked = entry.emit(NullCheck(entry.parameters.single));
      final viewed = entry.emit(UncheckedCast(checked, .object));
      entry.finish(Return(viewed));
      final body = IrFunction(target, [entry]);
      final program = IrProgram([], [body]);
      for (final (input, expected, throws) in [
        (FlowValue.unknown(.dynamicType), ValueType.object, true),
        (
          FlowValue.unknown(ValueType.integer.nullable),
          ValueType.integer,
          true,
        ),
        (FlowValue.unknown(.integer), ValueType.integer, false),
      ]) {
        final facts = ProgramFlow(program, [
          (target: target, arguments: [input]),
        ]).facts;
        expect(facts.valueOf(checked).unknownTypes, {expected});
        expect(facts.valueOf(viewed).unknownTypes, {expected});
        expect(facts.exitsOf(checked), (normal: true, exceptional: throws));
        expect(facts.effectsOf(checked).contains(Effect.mayThrow), throws);
      }
      final failed = ProgramFlow(program, [
        (
          target: target,
          arguments: [FlowValue.constant(const Constant.nullValue())],
        ),
      ]).facts;
      expect(failed.valueOf(checked).isBottom, isTrue);
      expect(failed.exitsOf(checked), (normal: false, exceptional: true));
      expect(failed.reachesOperation(viewed), isFalse);
    },
  );

  test('refinement queries use each invocation generic environment', () {
    final t = TypeParameterType('T')..initializeBound(.object.nullable);
    final target = FunctionTarget(
      uri,
      'choose',
      .object.nullable,
      [.object.nullable],
      typeParameters: [t],
    );
    final entry = Block(target.parameterTypes);
    final condition = entry.emit(TypeTest(entry.parameters.single, t));
    final refinement = condition.refinement(true)!;
    final yes = Block([refinement.type]);
    yes.finish(Return(yes.parameters.single));
    final no = Block()..finish(const Return(Constant.nullValue()));
    entry.finish(Branch(condition, Jump(yes, [refinement]), Jump(no)));
    final body = IrFunction(target, [entry, yes, no]);
    final main = FunctionTarget(uri, 'main', .voidType, []);
    final calls = Block();
    for (final (input, type) in <(Constant, ValueType)>[
      (const Constant.integer(7), .integer),
      (const Constant.string('kept'), .string),
      (const Constant.integer(7), .string),
    ]) {
      calls.emit(DirectCall(target, [input], typeArguments: [type]));
    }
    calls.finish(const Return());
    final program = IrProgram([], [
      body,
      IrFunction(main, [calls]),
    ]);
    final facts = ProgramFlow(program, [(target: main, arguments: [])]).facts;
    var reached = 0, rejected = 0;
    for (final activation in facts.activationsOf(target)) {
      final matches = facts.valueOf(condition, activation: activation).constant;
      final value = facts.valueOf(refinement, activation: activation);
      if (matches case ScalarConstant(value: true)) {
        reached++;
        expect(
          value.constant?.structuralKey,
          facts
              .valueOf(entry.parameters.single, activation: activation)
              .constant
              ?.structuralKey,
        );
        expect(
          value,
          facts
              .valueOf(yes.parameters.single, activation: activation)
              .withSources(value.sources),
        );
      } else {
        rejected++;
        expect(value.isBottom, isTrue);
      }
    }
    expect(reached, 2);
    expect(rejected, 1);
  });
}
