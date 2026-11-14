import 'package:dartc/frontend.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/src/optimizer/program_flow.dart';
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

  for (final example in <String, int Function()>{
    'rejectedCovariantCall': source.rejectedCovariantCall,
    'constructorValue': source.constructorValue,
    'genericFunctionValue': source.genericFunctionValue,
    'genericClosureValue': source.genericClosureValue,
    'genericConstructorValue': source.genericConstructorValue,
    'boundMethodValue': source.boundMethodValue,
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
