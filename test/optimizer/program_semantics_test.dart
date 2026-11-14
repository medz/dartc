import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
import 'package:dartc/src/optimizer/flow_value.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';
import 'fixtures/program_semantics.dart' as source;

void main() {
  late IrProgram program;
  setUpAll(() async {
    program = await AnalysisSession([
      'test/optimizer/fixtures/program_semantics.dart',
    ]).use((input) async => (await Lowering().lower(input)).program);
  });

  test(
    'source completion cannot be analyzed as the public Future result',
    () async {
      expect(await source.futureValue(), 7);
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'futureValue',
      );
      expect(
        () => ProgramFlow(program, [(target: entry.target, arguments: [])]),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'stage contract',
            contains('Normalize suspension before program flow'),
          ),
        ),
      );
    },
  );

  test('recursive input widening still applies changes to this caller', () {
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'recursionEffect',
    );
    expect(source.recursionEffect(0), 3);
    expect(source.recursionEffect(2), 9);
    final facts = ProgramFlow(program, [
      (target: entry.target, arguments: [FlowValue.unknown(.integer)]),
    ]).facts;
    expect(facts.returnedBy(entry.target).constant, isNull);
    expect(
      facts.returnedBy(entry.target).unknownTypes,
      contains(ValueType.integer),
    );
  });

  test('a nullable receiver keeps the null exception alternative', () {
    expect(source.nullableDynamic(source.ReturnsSeven()), 7);
    expect(() => source.nullableDynamic(null), throwsNoSuchMethodError);
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'nullableDynamic',
    );
    final facts = ProgramFlow(program, [
      (
        target: entry.target,
        arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
      ),
    ]).facts;
    expect(facts.thrownBy(entry.target).exception.isBottom, isFalse);
  });

  test(
    'an opaque API only invokes the private function with its actual argument',
    () {
      final observed = <int>[];
      source.exposePrivateArgument((callback) {
        observed.add(callback());
        observed.add(callback());
      });
      expect(observed, [8, 8]);
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'exposePrivateArgument',
      );
      final hidden = program.functions.singleWhere(
        (f) => f.target.name == 'hiddenIncrement',
      );
      final facts = ProgramFlow(program, [
        (
          target: entry.target,
          arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
        ),
      ]).facts;
      expect(
        facts.valueOf(hidden.entry.parameters.single).constant?.structuralKey,
        const Constant.integer(7).structuralKey,
      );
      expect(
        facts.returnedBy(hidden.target).constant?.structuralKey,
        const Constant.integer(8).structuralKey,
      );
    },
  );

  for (final (name, targetName, run) in [
    ('exposeInstantiatedClosure', 'local', source.exposeInstantiatedClosure),
    ('exposeInstantiatedMethod', 'echo', source.exposeInstantiatedMethod),
  ]) {
    test('an exposed generic callable preserves its instantiation: $name', () {
      final observed = <int>[];
      run((callback) => observed.add(callback(17)));
      expect(observed, [17]);
      final entry = program.functions.singleWhere((f) => f.target.name == name);
      final callable = program.functions.singleWhere(
        (f) => f.target.name == targetName,
      );
      final facts = ProgramFlow(program, [
        (
          target: entry.target,
          arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
        ),
      ]).facts;
      expect(facts.definitions, contains(callable.target));
      expect(facts.returnedBy(callable.target).unknownTypes, {
        ValueType.integer,
      });
    });
  }

  for (final example in <String, int Function()>{
    'rejectedCovariantCall': source.rejectedCovariantCall,
    'constructorValue': source.constructorValue,
    'genericFunctionValue': source.genericFunctionValue,
    'genericBoundMethodValue': source.genericBoundMethodValue,
    'genericBoundMethodOtherType': source.genericBoundMethodOtherType,
    'genericClosureValue': source.genericClosureValue,
    'genericConstructorValue': source.genericConstructorValue,
    'boundMethodValue': source.boundMethodValue,
    'returnedClosures': source.returnedClosures,
    'dynamicEffects': source.dynamicEffects,
    'dynamicRejectedArgument': source.dynamicRejectedArgument,
    'noSuchMethodEffects': source.noSuchMethodEffects,
    'dynamicFunctionValue': source.dynamicFunctionValue,
    'dynamicFunctionRejectsArgument': source.dynamicFunctionRejectsArgument,
    'dynamicMethodValue': source.dynamicMethodValue,
  }.entries) {
    test(example.key, () {
      final entry = program.functions.singleWhere(
        (f) => f.target.name == example.key,
      );
      final expected = example.value();
      expect(IrInterpreter(program, {}).run(entry, []), expected);
      final facts = ProgramFlow(program, [
        (target: entry.target, arguments: []),
      ]).facts;
      expect(
        facts.returnedBy(entry.target).constant?.structuralKey,
        Constant.integer(expected).structuralKey,
      );
    });
  }
}
