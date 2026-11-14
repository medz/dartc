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

  test('missing dispatch requires its real Invocation implementation', () {
    expect(source.noSuchMethodEffects(), 48);
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'noSuchMethodEffects',
    );
    expect(
      () => ProgramFlow(program, [(target: entry.target, arguments: [])]),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'stage contract',
          contains('Normalize dynamic dispatch'),
        ),
      ),
    );
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

  test('an exposed constructor publishes its initialized object fields', () {
    final observed = <int>[];
    source.exposeConstructor((construct) {
      final product = construct();
      expect(product.kind, int);
      observed.add(product.callback());
    });
    expect(observed, [23]);
    final entry = program.functions.singleWhere(
      (f) => f.target.name == 'exposeConstructor',
    );
    final callback = program.functions.singleWhere(
      (f) => f.target.name == 'constructedCallback',
    );
    final constructor = program.functions.singleWhere(
      (f) =>
          f.target.owner?.name == 'CallbackProduct' &&
          f.target.kind == .initializer,
    );
    final facts = ProgramFlow(program, [
      (
        target: entry.target,
        arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
      ),
    ]).facts;
    expect(facts.definitions, contains(callback.target));
    expect(
      facts.returnedBy(callback.target).constant?.structuralKey,
      const Constant.integer(23).structuralKey,
    );
    expect(
      facts.valueOf(constructor.entry.parameters.first).objects,
      hasLength(1),
    );
    expect(
      facts.valueOf(constructor.entry.parameters.first).unknownTypes,
      isEmpty,
    );
  });

  test(
    'an exposed generic constructor does not choose one external type argument',
    () {
      source.exposeUnappliedConstructor((construct) {
        expect(construct<int>().kind, int);
        expect(construct<String>().kind, String);
      });
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'exposeUnappliedConstructor',
      );
      final constructor = program.functions.singleWhere(
        (f) =>
            f.target.owner?.name == 'CallbackProduct' &&
            f.target.kind == .initializer,
      );
      final facts = ProgramFlow(program, [
        (
          target: entry.target,
          arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
        ),
      ]).facts;
      expect(facts.definitions, contains(constructor.target));
      final reified = constructor.blocks
          .expand((block) => block.instructions)
          .whereType<ReifyType>()
          .single;
      expect(facts.valueOf(reified).constant, isNull);
      expect(facts.valueOf(reified).unknownTypes, {ValueType.typeType});
    },
  );

  test(
    'an exception object crossing an external boundary exposes its fields',
    () {
      final observed = <int>[];
      source.exposeThrowingFunction((throwing) {
        try {
          throwing();
        } on source.CallbackProduct<int> catch (product) {
          observed.add(product.callback());
        }
      });
      expect(observed, [23]);
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'exposeThrowingFunction',
      );
      final callback = program.functions.singleWhere(
        (f) => f.target.name == 'constructedCallback',
      );
      final facts = ProgramFlow(program, [
        (
          target: entry.target,
          arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
        ),
      ]).facts;
      expect(facts.definitions, contains(callback.target));
      expect(
        facts.returnedBy(callback.target).constant?.structuralKey,
        const Constant.integer(23).structuralKey,
      );
    },
  );

  test(
    'a failed external construction does not publish the unfinished object',
    () {
      source.exposeFailingConstructor((construct) {
        expect(construct, throwsA(7));
      });
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'exposeFailingConstructor',
      );
      final callback = program.functions.singleWhere(
        (f) => f.target.name == 'unexposedCallback',
      );
      final facts = ProgramFlow(program, [
        (
          target: entry.target,
          arguments: [FlowValue.unknown(entry.target.parameterTypes.single)],
        ),
      ]).facts;
      expect(facts.definitions, isNot(contains(callback.target)));
    },
  );

  test(
    'storing a callback into an external object exposes the stored callable',
    () {
      final destination = source.ExternalSlot();
      source.publishCallback(destination);
      expect(destination.callback!(), 23);
      final entry = program.functions.singleWhere(
        (f) => f.target.name == 'publishCallback',
      );
      final callback = program.functions.singleWhere(
        (f) => f.target.name == 'constructedCallback',
      );
      final facts = ProgramFlow(
        program,
        const [],
        openEntries: [entry.target],
      ).facts;
      expect(facts.definitions, contains(callback.target));
      expect(
        facts.returnedBy(callback.target).constant?.structuralKey,
        const Constant.integer(23).structuralKey,
      );
    },
  );

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
